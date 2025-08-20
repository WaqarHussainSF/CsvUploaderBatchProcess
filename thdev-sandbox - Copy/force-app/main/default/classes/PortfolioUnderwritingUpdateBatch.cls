// Batch Apex for processing underwriting records
public class PortfolioUnderwritingUpdateBatch implements Database.Batchable<SObject> {
    private List<PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord> csvRecords;
    
    public PortfolioUnderwritingUpdateBatch(List<PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord> records) {
        this.csvRecords = records;
    }
    
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Set<Id> opportunityIds = new Set<Id>();
        for (PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord record : csvRecords) {
            opportunityIds.add(record.OpportunityId);
        }
        return Database.getQueryLocator([
            SELECT Opportunity__c, Status__c, Purchase_Offer__c, Estimated_Rent__c, 
            Contingency__c, Property_Taxes__c, Underwriting_Notes__c,
            Property_Questionnaire__c,
            Fixed_Assumptions__c,
            Opportunity__r.StageName
            FROM Underwriting__c
            WHERE Version__c = 'Latest' AND Opportunity__c IN :opportunityIds
        ]);
    }
    
    public void execute(Database.BatchableContext bc, List<Underwriting__c> existingRecords) {
        Map<Id, PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord> recordMap = new Map<Id, PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord>();
        for (PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord record : csvRecords) {
            recordMap.put(record.OpportunityId, record);
        }
        
        List<Property_Questionnaire__c> PQsToUpdate = new List<Property_Questionnaire__c>();
        List<Fixed_Assumptions__c> FAsToUpdate = new List<Fixed_Assumptions__c>();
        List<Opportunity> OppsToUpdate = new List<Opportunity>();
        
        for (Underwriting__c record : existingRecords) {
            PortfolioUnderwritingCsvUploader.UnderwritingCSVRecord csvData = recordMap.get(record.Opportunity__c);

            String Status = TrimText(csvData.Status);
            Decimal PurchaseOffer = convertStringToDecimal(csvData.PurchaseOffer);
            Decimal RentOffer = convertStringToDecimal(csvData.RentOffer);
            Decimal Contingency = convertStringToDecimal(csvData.Contingency);
            Decimal PropertyTaxes = convertStringToDecimal(csvData.PropertyTaxes);
            Decimal Insurance = convertStringToDecimal(csvData.Insurance);
            String UnderwritingNotes = csvData.UnderwritingNotes;
            

            if (csvData != null &&
                (PurchaseOffer != null  ||
                RentOffer != null ||
                Contingency != null ||
                PropertyTaxes != null ||
                Insurance != null ||
                String.isNotBlank(UnderwritingNotes)
                )
            ) {
                if(String.isNotBlank(Status))
                    record.Status__c = Status;
                
                if(PurchaseOffer != NULL)
                    record.Purchase_Offer__c = PurchaseOffer;
                if(RentOffer != NULL)
                    record.Estimated_Rent__c = RentOffer;
                if(Contingency != NULL)
                    record.Contingency__c = Contingency;
                if(PropertyTaxes != NULL)
                    record.Property_Taxes__c = PropertyTaxes;
                if(String.isNotBlank(UnderwritingNotes))
                    record.Underwriting_Notes__c = UnderwritingNotes;
                
                if(record.Property_Questionnaire__c != NULL && PropertyTaxes != NULL && record.Opportunity__r.StageName != 'Closed Won' && record.Opportunity__r.StageName != 'Closed Lost'){
                    Property_Questionnaire__c pq = new Property_Questionnaire__c();
                    pq.Id = record.Property_Questionnaire__c;
                    pq.Tax_Amount__c = PropertyTaxes;
                    PQsToUpdate.add(pq);
                }
                
                if(record.Fixed_Assumptions__c != NULL && Insurance != NULL && PurchaseOffer != NULL){
                    Fixed_Assumptions__c fa = new Fixed_Assumptions__c();
                    fa.Id = record.Fixed_Assumptions__c;
                    fa.Newer_Insurance_of_Value__c = (Insurance/PurchaseOffer) * 100;
                    fa.Older_Insurance_of_Value__c = (Insurance/PurchaseOffer) * 100;
                    FAsToUpdate.add(fa);
                }

                if(String.isNotBlank(Status) && Status.equalsIgnoreCase('declined')){
                    Opportunity opp = new Opportunity();
                    opp.Id = record.Opportunity__c;
                    opp.StageName = 'Closed Lost';
                    opp.Stage_Status__c = NULL;
                    opp.Loss_Reason__c = 'TH declined to make offer';
                    opp.Closed_Lost_Reason_Subcategory__c = 'Other';
                    opp.Opportunity_Closed_Lost_Notes__c = 'Bulk portfolio decline';
                    OppsToUpdate.add(opp);
                }
            }
        }
        System.debug('existingRecords::'+existingRecords);
        System.debug('PQsToUpdate::'+PQsToUpdate);
        System.debug('FAsToUpdate::'+FAsToUpdate);
        System.debug('OppsToUpdate::'+OppsToUpdate);

        if(existingRecords.size() > 0){
            update existingRecords;
        }
        if(PQsToUpdate.size() > 0){
            update PQsToUpdate;
        }
        if(FAsToUpdate.size() > 0){
            update FAsToUpdate;
        }
        if(OppsToUpdate.size() > 0){
            update OppsToUpdate;
        }
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch processing completed successfully.');
    }


    public static decimal convertStringToDecimal(string StringValue){
        if(string.isBlank(StringValue)){
            return NULL;
        }else{
            //remove any character that is not a decimal point or a digit
            StringValue = StringValue.replaceAll('[^.\\d]','');
            if(String.isBlank(StringValue)){
                return NULL;
            }else{
                return Decimal.valueOf(StringValue);
            }
        }
    }
    public static String TrimText(string StringValue){
        if(string.isBlank(StringValue)){
            return NULL;
        }else{
            return StringValue.trim();
        }
    }
}