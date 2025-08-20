public class PortfolioUnderwritingCsvUploader {
    
    @AuraEnabled
    public static String saveFile(String csvData) {
        
        System.debug(csvData);
        
        if (String.isEmpty(csvData)) {
            throw new AuraHandledException('No records found in the CSV.');
        }
        
        // Deserialize JSON String to List
        List<UnderwritingCSVRecord> csvRecords = (List<UnderwritingCSVRecord>) JSON.deserialize(csvData, List<UnderwritingCSVRecord>.class);
        
        System.debug('Parsed Records: ' + JSON.serialize(csvRecords)); // Verify parsed data
        
        if (csvRecords.isEmpty()) {
            throw new AuraHandledException('Parsed list is empty.');
        }
        
        PortfolioUnderwritingUpdateBatch batch = new PortfolioUnderwritingUpdateBatch(csvRecords);
        
        Id batchJobId = Database.executeBatch(batch, 10);
        System.debug('batchJobId::'+batchJobId);
        return batchJobId;  // Send this ID to LWC for tracking progress
    }
    
    @AuraEnabled(cacheable=false)
    public static String getBatchStatus(String jobId) {
        if (String.isEmpty(jobId)) {
            return 'No job found.';
        }
        
        AsyncApexJob job = [SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors, ExtendedStatus
                            FROM AsyncApexJob WHERE Id = :jobId LIMIT 1];
        
        Integer totalRecords = job.TotalJobItems != null ? job.TotalJobItems : 0;
        Integer processedRecords = job.JobItemsProcessed != null ? job.JobItemsProcessed : 0;
        Integer errorCount = job.NumberOfErrors != null ? job.NumberOfErrors : 0;
        Integer successCount = processedRecords - errorCount;
        
        String statusMessage;
        
        if (job.Status == 'Completed' && errorCount == 0) {
            statusMessage = 'Batch processing completed successfully. ' + successCount + ' ' + getBatchText(successCount) + ' processed.';
        } else if (job.Status == 'Completed' && errorCount > 0) {
            statusMessage = 'Batch processing completed with some errors. ' + 
                successCount + ' ' + getBatchText(successCount) + ' processed successfully out of ' + 
                totalRecords + ', but ' + errorCount + ' ' + getBatchText(errorCount) + ' failed.';
            
            if (!String.isEmpty(job.ExtendedStatus)) {
                statusMessage += ' ' + job.ExtendedStatus;
            }
        } else if (job.Status == 'Failed') {
            statusMessage = 'Batch processing failed. No records were processed.';
        } else {
            statusMessage = 'Batch is in progress... ' + 
                processedRecords + ' ' + getBatchText(processedRecords) + ' processed so far out of ' + 
                totalRecords + '.';
            
            if (!String.isEmpty(job.ExtendedStatus)) {
                statusMessage += ' ' + job.ExtendedStatus;
            }
        }
        
        return statusMessage;
    }
    
    // Helper function for batch/batches
    private static String getBatchText(Integer count) {
        return count == 1 ? 'batch' : 'batches';
    }
    
    // Data structure for CSV records
    public class UnderwritingCSVRecord {
        @AuraEnabled public Id OpportunityId;
        @AuraEnabled public String Status;
        @AuraEnabled public String PurchaseOffer;
        @AuraEnabled public String RentOffer;
        @AuraEnabled public String Contingency;
        @AuraEnabled public String PropertyTaxes;
        @AuraEnabled public String Insurance;
        @AuraEnabled public String UnderwritingNotes;
    }
}