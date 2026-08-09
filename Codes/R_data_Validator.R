# Team Excel-lence

########################## Packages #######################
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
  `File name` = type_enum(values = c("sales_data", "claims_data"), description = "Name of the target dataset."),
  `Column name` = type_string(description = "Exact name of the column as present in the dataset."),
  `Data type` = type_enum(values = c("String", "Number", "Date"), description = "Inferred statistical/R data type."),
  `Description` = type_string(description = "Elaborate business and technical description. Explain column meaning, potential relationship to other columns (e.g. Sale Date <= Claim Date), and key validation conditions needed downstream.")
)

Column_str_describer_AI = chat_google_gemini(
    system_prompt = "
    You are an expert insurance data architect analyzing datasets for ABC General Insurance Company.
    For each attached dataset (e.g. vehicle sales, warranty claims):
    1. Inspect all columns, data types, sample values, and statistical distributions.
    2. Determine nullability, primary key constraints, and allowable domains/ranges.
    3. Formulate exhaustive column descriptions focusing on business context and inter-table/intra-table relationships (e.g., cross-column comparisons, foreign key lookups between sales and claims).",
    model = "gemini-3.1-flash-lite"
)

Validation_rules_AI_output = type_object(
  `Rule ID` = type_string(description = "Unique identifier for the rule e.g. R001, R002."),
  `File name` = type_enum(values = c("sales_data", "claims_data"), description = "Name of the dataset to validate."),
  `Rule type` = type_enum(values = c("missing", "unique", "positive", "range", "compare", "exists", "allowed_values", "outlier"), description = "Category of the data validation rule."),
  `Column1` = type_string(description = "Primary column being validated."),
  `Column2` = type_string(description = "Secondary column, required for 'compare' or cross-column rules. Leave empty/NA if not applicable."),
  `Reference dataset` = type_string(description = "Reference dataset for cross-table rules (e.g. sales_data for claims validation). Leave empty/NA if not applicable."),
  `Reference column` = type_string(description = "Reference column in the reference dataset (e.g. VIN). Leave empty/NA if not applicable."),
  `Parameter` = type_string(description = "Allowed values list, min/max range criteria, or comparison condition. Leave empty/NA if not applicable."),
  `Severity` = type_enum(values = c("Error", "Warning"), description = "Severity level if the rule fails."),
  `Description` = type_string(description = "Detailed explanation of what this rule validates and why.")
)

Validation_rules_AI = chat_google_gemini(
  system_prompt = "
  You are an actuarial data validation expert for ABC General Insurance Company.
  Using the provided data schema and dataset descriptions, generate a comprehensive list of data validation rules.
  Allowed rule types are strictly: missing, unique, positive, range, compare, exists, allowed_values, outlier.
  Consider single-column checks, cross-column logic within the same dataset, and cross-table validation (such as matching claim VINs/dates against sales records).
  Generate as many rules as possible. The user will then review if they want to run that rule or not.
  Consider all relationships, multiple validations even within the same column is also possible.
  # For example:
  1. Sale_ID should always be unique, it can not be null, it should be comparable with the claims database, etc.
  2. Sale_Price_USD should always be positive, can not be 0, can not be NULL, etc.
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
  "Sales sample data: ", paste0(capture.output(head(sales_data_raw)), collapse = "\n"), "\n",
  "Claims sample data: ", paste0(capture.output(head(claims_data_raw)), collapse = "\n"), "\n",
  "Sales structure: ", paste0(capture.output(str(sales_data_raw)), collapse = "\n"), "\n",
  "Claims structure: ", paste0(capture.output(str(claims_data_raw)), collapse = "\n"),
  collapse = "\n"
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

########################### Validation rules generator #####

### Generate validation rules using Validation_rules_AI
rules_question = paste0(
  "Here is the verified data schema with descriptions for the datasets:\n",
  paste0(capture.output(Data_schema), collapse = "\n"), "\n\n",
  "Sales sample data:\n", paste0(capture.output(head(sales_data)), collapse = "\n"), "\n\n",
  "Claims sample data:\n", paste0(capture.output(head(claims_data)), collapse = "\n"), "\n\n",
  "Please generate a complete set of validation rules using rule types: missing, unique, positive, range, compare, exists, allowed_values, outlier."
)

validation_rules_DF = Validation_rules_AI$chat_structured(
  rules_question,
  type = type_array(
    items = Validation_rules_AI_output,
    description = "List of data validation rules for sales_data and claims_data."
  ),
  convert = TRUE
) |> as.data.frame()

# Save the validation rules into an Excel file called Validation_Rules.xlsx
write_xlsx(x = validation_rules_DF, path = paste0(Path, "/Output/Validation_Rules.xlsx"))
print("Validation rules generated and saved successfully")

############################################################