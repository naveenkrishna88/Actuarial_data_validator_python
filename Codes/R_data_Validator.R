# Team Excel-lence

########################### Packages #######################
### Load all necessary packages
library(readxl)
library(ellmer)
library(jsonlite)
library(writexl)
library(lubridate)
############################################################

########################## Path ############################

Path = Sys.getenv("Excel_lence_Path")

############################################################

########################### Models #########################

Column_str_describer_AI_output = type_object(
  `File name` = type_enum(values = c("sales_data", "claims_data"), description = "Given a list of data frames, identify the file name."),
  `Column name` = type_string(description = "Retrun only the column name."),
  `Data type` = type_enum(values = c("String", "Number", "Date")),
  `Description` = type_string(description = "Description should be as elaborate as possible.
                              This will be used by another AI model to create data validation rules.
                              So, any cross table validations or comparisons among columns should be considered.")
)

Column_str_describer_AI = chat_google_gemini(
    system_prompt = "
    For each of the attached data set belonging to the ABC general insurance company, identify the data type of each column and provide a describtion of what column defines.",
    model = "gemini-3.1-flash-lite"
)

Validation_rules_AI = chat_google_gemini(
  system_prompt = "
  You are an actuarial data validation expert.
  Generate validation rules for the supplied datasets.
  You may ONLY use these rule types:
    missing, unique, positive, range, compare, exists, equal, allowed_values, regex.
  Do not invent new rule types.
  Every rule must contain:
    rule_id, dataset, rule_type, column1, column2, reference_dataset, reference_column, parameter, severity, description.
  Return ONLY a JSON object.
  ",
  model = "gemini-3.1-flash-lite"
)

###########################################################

########################### Functions #####################

Date_converter_fxn = function(date_col_to_fix){
  
  date_col_to_fix = as.character(date_col_to_fix)
  date_fixed = as.Date(rep(NA, length(date_col_to_fix)))
  
  for(i in 1:length(date_col_to_fix)){
    if(is.na(date_col_to_fix[i])){
      next
    } else if (nchar(date_col_to_fix[i]) == 5){
      date_fixed[i] = as.Date(as.numeric(date_col_to_fix[i]), origin = "1899-12-30")
    } else if (nchar(date_col_to_fix[i]) == 10){
      date_fixed[i] = as.Date(parse_date_time(date_col_to_fix[i], orders = c("ymd", "dmy", "mdy", "d-b-Y", "d-b-y")))
    }
  }
  return(date_fixed)
}

############################################################


########################### Data prep ######################

### Raw data read in
sales_data_raw = read_excel(path = paste0(Path, "/Input/EV_Vehicle_Sales_Data_500.xlsx")) |> as.data.frame()
claims_data_raw = read_excel(path = paste0(Path, "/Input/EV_Warranty_Claims_Synthetic_Flawed_150-1.xlsx")) |> as.data.frame()
print("Excel files loaded successfully")

### Execute Column_str_describer and save the excel OP
question = paste0(
  "The attached are 2 data tables from ABC insurance company.
  Sales refers to all the vehicle sales made in the year, 
  Claims refers to all the claims made in the year", "\n",
  "Sales sample data: ", capture.output(head(sales_data_raw)), "\n",
  "Claims sample data: ", capture.output(head(claims_data_raw)), "\n",
  "Sales structure: ", capture.output(str(sales_data_raw)), "\n",
  "Claims structure: ", capture.output(str(claims_data_raw))
)

response_DF = Column_str_describer_AI$chat_structured(question,
                                                        type = type_array(items = Column_str_describer_AI_output, description = 
                                                                            "The attached are 2 data tables from ABC insurance company. 
                                                                          Sales refers to all the vehicle sales made in the year, 
                                                                          Claims refers to all the claims made in the year"),
                                                        convert = TRUE) |> as.data.frame()

# Save the response_DF into an excel file called Data_Schema
write_xlsx(x = response_DF, path = paste0(Path, "/Output/Data_Schema.xlsx"))

### Once the user verifies the Data_Schema, proceed to Data cleaning
Data_schema = read_excel(path = paste0(Path, "/Output/Data_Schema.xlsx")) |> as.data.frame()

# The cleaned data are stored in sales_data and claims_data
sales_data = sales_data_raw
claims_data = claims_data_raw

our_datasets = list("sales_data" = sales_data, "claims_data" = claims_data)

# We have some notoriously formatted dates: NA           "44629"      "44062"      "45273"      "44930"      "05/30/2023" "43630"  
for(i in 1:nrow(Data_schema)){
  col_type = Data_schema$`Data type`[i]
  file_name = Data_schema$`File name`[i]
  col_name = Data_schema$`Column name`[i]

  if(col_type == "Date"){
    our_datasets[[file_name]][[col_name]] = Date_converter_fxn(date_col_to_fix = our_datasets[[file_name]][[col_name]])
  }
  
  if(col_type == "Number"){
    our_datasets[[file_name]][[col_name]] = as.numeric(our_datasets[[file_name]][[col_name]])
  }
}

sales_data = our_datasets$sales_data
claims_data = our_datasets$claims_data

print("Data cleaning complete")

############################################################

########################### Data prep ######################

############################################################