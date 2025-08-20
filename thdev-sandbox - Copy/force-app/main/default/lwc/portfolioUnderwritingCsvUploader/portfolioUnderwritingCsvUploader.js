import { LightningElement, api, track } from 'lwc';
import saveFile from '@salesforce/apex/PortfolioUnderwritingCsvUploader.saveFile';
import getBatchStatus from '@salesforce/apex/PortfolioUnderwritingCsvUploader.getBatchStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';


export default class PortfolioUnderwritingCsvUploader extends LightningElement {
    @api recordId;
    @api headerTextVal = "Upload a CSV File to Update Portfolio Underwriting Records";
    fileName = '';
    UploadFile = 'Submit CSV File';
    showLoadingSpinner = false;
    disableSaveBtn = false;
    filesUploaded = [];
    csvData = [];

    batchStatus = '';
    batchJobId = null;
    intervalId = null;  // Store interval ID for polling

    handleFilesChange(event) {
        if (event.target.files.length > 0) {
            this.filesUploaded = event.target.files;
            this.fileName = event.target.files[0].name;
        }
    }

    handleSave() {
        if (this.filesUploaded.length > 0) {
            this.uploadHelper();
        } else {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select a CSV file to upload!',
                variant: 'error'
            }));
        }
    }

    uploadHelper() {
        this.disableSaveBtn = true;
        this.showLoadingSpinner = true;
        
        let fileReader = new FileReader();
        fileReader.onloadend = (() => {
            let fileContents = fileReader.result;
            console.log(fileContents);
            this.csvData = this.parseCSV(fileContents);
            this.saveToApex();
        });
        fileReader.readAsText(this.filesUploaded[0]);
    }

    saveToApex() {
        
        let payload = JSON.stringify(this.csvData);
        console.log(payload);
        saveFile({ csvData: payload })
        .then(jobId => {
            console.log('jobId::',jobId);
            this.batchJobId = jobId;
            this.batchStatus = 'Batch Queued...';
            this.startPolling();

            // Reset upload state
            this.disableSaveBtn = false;
            this.fileName = '';
            this.filesUploaded = [];
            this.csvData = [];
        })
        .catch(error => {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body.message,
                variant: 'error'
            }));
            // Reset upload state
            this.disableSaveBtn = false;
            this.fileName = '';
            this.filesUploaded = [];
            this.csvData = [];
        })
        .finally(() => {
            this.showLoadingSpinner = false;
        });
    }

    // Polling function to check batch progress every 5 seconds
    startPolling() {
        setTimeout(() => {  // Delay before first polling check
            this.intervalId = setInterval(() => {
                if (!this.batchJobId) return;
    
                console.log('Checking batch status for: ', this.batchJobId);
    
                getBatchStatus({ jobId: this.batchJobId })
                    .then(status => {
                        console.log('Batch status received: ', status);
                        this.batchStatus = status;
    
                        // Stop polling when completed or failed
                        if (status.trim().toLowerCase().includes('batch processing completed') || 
                            status.trim().toLowerCase().includes('batch processing failed')) {
                            console.log('inside clear interval');
                            clearInterval(this.intervalId);
                            this.intervalId = null;  // Prevent multiple clearInterval calls
                        }

                    })
                    .catch(error => {
                        console.error('Error fetching batch status:', error);
                        clearInterval(this.intervalId);
                        this.intervalId = null;  // Prevent multiple clearInterval calls
                    });
            }, 5000); // Poll every 5 seconds
        }, 3000);  // Initial delay of 3 seconds
    }
    

    parseCSV(csvData) {
        let rows = csvData.split(/\r?\n/).filter(row => row.trim() !== '');
        let headers = this.parseCSVRow(rows[0]);
        let parsedData = [];
    
        for (let i = 1; i < rows.length; i++) {
            let columns = this.parseCSVRow(rows[i]);
            if (columns.length === headers.length) { // Ensure correct column alignment
                let record = {
                    opportunityId: this.getColumnValue(headers, columns, "Opportunity Id"),
                    status: this.getColumnValue(headers, columns, "Status"),
                    purchaseOffer: this.getColumnValue(headers, columns, "Purchase Offer"),
                    rentOffer: this.getColumnValue(headers, columns, "Rent Offer"),
                    contingency: this.getColumnValue(headers, columns, "Contingency"),
                    propertyTaxes: this.getColumnValue(headers, columns, "Property Taxes"),
                    insurance: this.getColumnValue(headers, columns, "Insurance"),
                    underwritingNotes: this.getColumnValue(headers, columns, "Underwriting Notes")
                };
                parsedData.push(record);
            }
        }
        return parsedData;
    }
    
    parseCSVRow(row) {
        const regex = /(?:^|,)("(?:[^"]|"")*"|[^,]*)/g;
        let matches = [];
        let match;
        while ((match = regex.exec(row)) !== null) {
            let value = match[1].trim();
            if (value.startsWith('"') && value.endsWith('"')) {
                value = value.slice(1, -1).replace(/""/g, '"'); // Handle escaped quotes
            }
            matches.push(value);
        }
        return matches;
    }
    
    getColumnValue(headers, columns, columnName) {
        let index = headers.indexOf(columnName);
        return index !== -1 ? columns[index] : "";
    }
}