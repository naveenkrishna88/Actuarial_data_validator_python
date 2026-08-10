# Team Excel-lence

################################ Packages ##################################
# Load all required R packages for file I/O, AI chat, JSON handling, and date parsing
library(readxl) # Reading raw Excel files (.xlsx)
library(ellmer) # Google Gemini API integration (chat_google_gemini & structured outputs)
library(jsonlite) # Converting data frames to JSON for LLM prompts
library(writexl) # Exporting output data frames to Excel
library(lubridate) # Standardizing and parsing messy date strings
############################################################################

################################ Path ######################################
# Environment path setup to locate Input/ and Output/ directories
Path <- Sys.getenv("Excel_lence_Path")
############################################################################

################################ Models ####################################

# Model 1: Column Schema Describer Schema
# Defines structured output for inspecting dataset columns and inferring data types/descriptions
Column_str_describer_AI_output <- type_object(
  `File name` = type_enum(values = c("sales_data", "claims_data"), description = "Name of the target dataset."),
  `Column name` = type_string(description = "Exact name of the column as present in the dataset."),
  `Data type` = type_enum(values = c("String", "Number", "Date"), description = "Inferred statistical/R data type."),
  `Description` = type_string(description = "Elaborate business and technical description. Explain column meaning, potential relationship to other columns (e.g. Sale Date <= Claim Date), and key validation conditions needed downstream.")
)

# Gemini AI client for dataset schema extraction
Column_str_describer_AI <- chat_google_gemini(
  system_prompt = "
    You are an expert insurance data architect analyzing datasets for ABC General Insurance Company.
    For each attached dataset (e.g. vehicle sales, warranty claims):
    1. Inspect all columns, data types, sample values, and statistical distributions.
    2. Determine nullability, primary key constraints, and allowable domains/ranges.
    3. Formulate exhaustive column descriptions focusing on business context and inter-table/intra-table relationships (e.g., cross-column comparisons, foreign key lookups between sales and claims).",
  model = "gemini-3.1-flash-lite"
)

Validation_rules_AI_output <- type_object(
  `Rule ID` = type_string(description = "Unique identifier for the rule e.g. R001, R002."),
  `Table 1` = type_enum(values = c("sales_data", "claims_data"), description = "Primary dataset to validate."),
  `Column 1` = type_string(description = "Primary column in Table 1 being validated."),
  `Rule type` = type_enum(values = c("missing", "unique", "positive", "range", "greater_than", "equals", "exists", "allowed_values"), description = "Category of the data validation rule."),
  `Table 2` = type_string(description = "Secondary/reference dataset for cross-table rules (e.g. sales_data). Leave empty/NA for intra-table rules."),
  `Column 2` = type_string(description = "Secondary column in Table 1 (or Table 2) for 'greater_than', 'equals', or 'exists' rules. Leave empty/NA if not applicable."),
  `Parameter` = type_string(description = "Required parameter. For 'allowed_values': comma-separated categories. For 'range': min and max values ('min, max'). Leave empty/NA for others."),
  `Severity` = type_enum(values = c("Error", "Warning"), description = "Severity level if the rule fails."),
  `Description` = type_string(description = "Detailed explanation of what this rule validates and why.")
)

# Gemini AI client for generating validation rules
Validation_rules_AI <- chat_google_gemini(
  system_prompt = "
  You are an actuarial data validation expert for ABC General Insurance Company.
  Using the provided data schema and sample dataset values, generate an EXHAUSTIVE list of data validation rules (aim for 50+ total rules). But do not create stupid rules like setting ranges for VIN, Claim ID etc..
  Allowed rule types are strictly: missing, unique, positive, range, greater_than, equals, exists, allowed_values.

  CRITICAL MANDATORY INSTRUCTIONS:
  1. EVERY SINGLE COLUMN in both sales_data and claims_data MUST have multiple rules defined for it.
  2. For EVERY column, evaluate if a 'missing' (null check) rule should exist. Do NOT omit missing checks!
  3. For EVERY numeric column (prices, costs, IDs, years, counts), evaluate 'positive' and/or 'range' rules.
  4. For EVERY categorical/string column (status, state, model, claim type), evaluate 'allowed_values' and extract all unique values from sample data.
  5. For EVERY ID/Key column (Sale_ID, Claim_ID, VIN), define 'unique' in Table 1 and 'exists' (foreign key lookup in Table 2).
  6. For ALL date and numeric comparisons (e.g., Claim Date vs Sale Date, Repair Cost vs Claim Amount), use 'greater_than' (swap Column 1/Column 2 if checking less than) or 'equals'. If comparing across tables, specify Table 2.

  CRITICAL PARAMETER RULES:
  - For 'allowed_values': Provide a comma-separated list of all valid categories observed in the dataset.
  - For 'range': Provide exact numeric boundaries as 'min, max' (e.g., '0, 100000').
  - For 'missing', 'unique', 'positive', 'greater_than', 'equals', 'exists': Parameter should be left empty/NA.

  Do NOT stop early. You MUST generate as many executable rules logically possible across all columns and relationships.",
  model = "gemini-3.1-flash-lite"
)

############################################################################

################################ Functions #################################

# Function: Date_converter_fxn
# Converts messy Excel serial numbers (e.g., 44629) or formatted strings into standardized R Date objects
Date_converter_fxn <- function(date_col_to_fix) {
  date_col_to_fix <- as.character(date_col_to_fix)
  date_fixed <- as.Date(rep(NA, length(date_col_to_fix)))

  for (i in 1:length(date_col_to_fix)) {
    if (is.na(date_col_to_fix[i])) {
      next
    } else if (nchar(date_col_to_fix[i]) == 5) {
      date_fixed[i] <- as.Date(as.numeric(date_col_to_fix[i]), origin = "1899-12-30")
    } else if (nchar(date_col_to_fix[i]) == 10) {
      date_fixed[i] <- as.Date(parse_date_time(date_col_to_fix[i], orders = c("ymd", "dmy", "mdy", "d-b-Y", "d-b-y")))
    }
  }
  return(date_fixed)
}

############################################################################

################################# Validator functions ######################

# Helper: Key lookup for cross-table comparisons
# Matches key1 from primary table to key2 in reference table and retrieves target_col
lookup_ref_column <- function(key1, ref_key2, ref_target_col) {
  idx <- match(key1, ref_key2)
  ref_target_col[idx]
}

# 1. Missing check (returns TRUE where col1 is NA or blank)
validate_missing <- function(col1) {
  is.na(col1) | trimws(as.character(col1)) == ""
}

# 2. Unique check (returns TRUE for duplicate entries)
validate_unique <- function(col1) {
  duplicated(col1)
}

# 3. Positive check (returns TRUE where col1 is non-null and <= 0)
validate_positive <- function(col1) {
  !is.na(col1) & col1 <= 0
}

# 4. Range check (returns TRUE where col1 falls outside [min_val, max_val])
validate_range <- function(col1, min_val = -Inf, max_val = Inf) {
  !is.na(col1) & (col1 < min_val | col1 > max_val)
}

# 5. Greater Than check (checks if col1 > col2, returns TRUE where col1 <= col2)
validate_greater_than <- function(col1, col2) {
  valid_mask <- !is.na(col1) & !is.na(col2)
  violation <- col1 <= col2
  valid_mask & violation
}

# 6. Equals check (checks if col1 == col2, returns TRUE where col1 != col2)
validate_equals <- function(col1, col2) {
  valid_mask <- !is.na(col1) & !is.na(col2)
  violation <- col1 != col2
  valid_mask & violation
}

# 7. Exists / Foreign Key lookup check (returns TRUE where col1 is missing from ref_col)
validate_exists <- function(col1, ref_col) {
  !is.na(col1) & !(col1 %in% ref_col)
}

# 8. Allowed values check (returns TRUE where col1 is not in allowed_set, handling whitespace)
validate_allowed_values <- function(col1, allowed_set) {
  clean_col1 <- trimws(as.character(col1))
  clean_allowed <- trimws(as.character(allowed_set))
  !is.na(col1) & !(clean_col1 %in% clean_allowed)
}

# Named lookup list mapping rule type strings directly to executable R functions
validator_tools <- list(
  "lookup_ref"     = lookup_ref_column,
  "missing"        = validate_missing,
  "unique"         = validate_unique,
  "positive"       = validate_positive,
  "range"          = validate_range,
  "greater_than"   = validate_greater_than,
  "equals"         = validate_equals,
  "exists"         = validate_exists,
  "allowed_values" = validate_allowed_values
)

############################################################################

################################ Data Schema generator #####################

# Step 1: Read raw input Excel files
sales_data_raw <- read_excel(path = file.path(Path, "Input", "EV_Vehicle_Sales_Data_500.xlsx")) |> as.data.frame()
claims_data_raw <- read_excel(path = file.path(Path, "Input", "EV_Warranty_Claims_Synthetic_Flawed_150-1.xlsx")) |> as.data.frame()
print("Excel files loaded successfully")

# Step 2: Query Gemini AI to analyze raw structure and generate Data_Schema
question <- paste0(
  "The attached are 2 data tables from ABC insurance company.
  Sales refers to all the vehicle sales made in the year,
  Claims refers to all the claims made in the year", "\n",
  "Sales sample data: ", paste0(capture.output(head(sales_data_raw, 50)), collapse = "\n"), "\n",
  "Claims sample data: ", paste0(capture.output(head(claims_data_raw, 50)), collapse = "\n"), "\n",
  "Sales structure: ", paste0(capture.output(str(sales_data_raw)), collapse = "\n"), "\n",
  "Claims structure: ", paste0(capture.output(str(claims_data_raw)), collapse = "\n"),
  collapse = "\n"
)

response_DF <- Column_str_describer_AI$chat_structured(
  question,
  type = type_array(
    items = Column_str_describer_AI_output,
    description = "The attached are 2 data tables from ABC insurance company. Sales refers to all vehicle sales made in the year, Claims refers to all claims made in the year."
  ),
  convert = TRUE
) |> as.data.frame()

# Step 3: Save Data_Schema to Output Excel
write_xlsx(x = response_DF, path = file.path(Path, "Output", "Data_Schema.xlsx"))

############################################################################

################################ Data cleaning #############################

# Step 4: Load verified Data_Schema and perform data type standardization
Data_schema <- read_excel(path = file.path(Path, "Output", "Data_Schema.xlsx")) |> as.data.frame()

sales_data <- sales_data_raw
claims_data <- claims_data_raw

our_datasets <- list("sales_data" = sales_data, "claims_data" = claims_data)

# Convert dates and numbers according to schema definitions
for (i in 1:nrow(Data_schema)) {
  col_type <- Data_schema$`Data type`[i]
  file_name <- Data_schema$`File name`[i]
  col_name <- Data_schema$`Column name`[i]

  if (col_type == "Date") {
    our_datasets[[file_name]][[col_name]] <- Date_converter_fxn(date_col_to_fix = our_datasets[[file_name]][[col_name]])
  }

  if (col_type == "Number") {
    our_datasets[[file_name]][[col_name]] <- as.numeric(our_datasets[[file_name]][[col_name]])
  }
}

print("Data cleaning complete")

############################################################################

################################ Validation rules generator ################

# Step 5: Query Gemini AI to generate exhaustive validation rules based on cleaned schema
rules_question <- paste0(
  "Here is the verified data schema with descriptions for the datasets:\n",
  jsonlite::toJSON(Data_schema, pretty = TRUE), "\n\n",
  "Sales sample data:\n", paste0(capture.output(head(sales_data, 50)), collapse = "\n"), "\n\n",
  "Claims sample data:\n", paste0(capture.output(head(claims_data, 50)), collapse = "\n"), "\n\n"
)

validation_rules_DF <- Validation_rules_AI$chat_structured(
  rules_question,
  type = type_array(
    items = Validation_rules_AI_output,
    description = "List of data validation rules for sales_data and claims_data."
  ),
  convert = TRUE
) |> as.data.frame()

# Step 6: Export generated validation rules to Output/Validation_Rules.xlsx
write_xlsx(x = validation_rules_DF, path = file.path(Path, "Output", "Validation_Rules.xlsx"))
print("Validation rules generated and saved successfully")

############################################################################

################################ Validation rules engine ###################

# Step 7: Deterministic Rule Execution Engine
# Reads Validation_Rules.xlsx and executes corresponding vanilla R validator functions
validation_rules_to_run <- read_excel(path = file.path(Path, "Output", "Validation_Rules.xlsx")) |> as.data.frame()

validation_errors_list <- list()

for (i in 1:nrow(validation_rules_to_run)) {
  rule <- validation_rules_to_run[i, ]

  rule_id <- rule$`Rule ID`
  t1_name <- rule$`Table 1`
  col1_name <- rule$`Column 1`
  rule_type <- rule$`Rule type`
  t2_name <- rule$`Table 2`
  col2_name <- rule$`Column 2`
  param <- rule$`Parameter`
  severity <- rule$`Severity`
  desc <- rule$`Description`

  # Target dataset and primary column vector
  df1 <- our_datasets[[t1_name]]
  col1 <- df1[[col1_name]]

  violation_mask <- rep(FALSE, nrow(df1))

  # Dispatch to appropriate validator function based on rule_type
  if (rule_type == "missing") {
    violation_mask <- validator_tools$missing(col1)
  } else if (rule_type == "unique") {
    violation_mask <- validator_tools$unique(col1)
  } else if (rule_type == "positive") {
    violation_mask <- validator_tools$positive(col1)
  } else if (rule_type == "allowed_values") {
    # Expect comma-separated string e.g. "Completed, Pending"
    allowed_set <- trimws(unlist(strsplit(as.character(param), ",")))
    violation_mask <- validator_tools$allowed_values(col1, allowed_set)
  } else if (rule_type == "range") {
    # Expect parameter like "0, 100" or "[0, 100]"
    num_params <- as.numeric(unlist(regmatches(param, gregexpr("-?\\d+\\.?\\d*", param))))
    min_v <- if (length(num_params) >= 1) num_params[1] else -Inf
    max_v <- if (length(num_params) >= 2) num_params[2] else Inf
    violation_mask <- validator_tools$range(col1, min_val = min_v, max_val = max_v)
  } else if (rule_type == "exists") {
    # Reference set lookup in Table 2 (Column 2 or default to Column 1 name in Table 2)
    t2_target_col <- if (!is.na(col2_name) && trimws(col2_name) != "") col2_name else col1_name
    ref_vec <- our_datasets[[t2_name]][[t2_target_col]]
    violation_mask <- validator_tools$exists(col1, ref_vec)
  } else if (rule_type %in% c("greater_than", "equals")) {
    # Resolve Column 2 (same-table or cross-table lookup via lookup_ref)
    if (!is.na(t2_name) && trimws(t2_name) != "") {
      key1 <- df1[[col1_name]]
      t2_key2 <- our_datasets[[t2_name]][[col1_name]]
      t2_target <- our_datasets[[t2_name]][[col2_name]]

      col2 <- validator_tools$lookup_ref(key1, t2_key2, t2_target)
    } else {
      col2 <- df1[[col2_name]]
    }

    if (rule_type == "greater_than") {
      violation_mask <- validator_tools$greater_than(col1, col2)
    } else if (rule_type == "equals") {
      violation_mask <- validator_tools$equals(col1, col2)
    }
  }

  # Log violations into validation report structure
  violated_rows <- which(violation_mask)
  if (length(violated_rows) > 0) {
    # Extract VIN if present in df1
    vin_col <- if ("VIN" %in% names(df1)) as.character(df1$VIN[violated_rows]) else rep(NA, length(violated_rows))

    # Value for Column 1
    val1 <- as.character(col1[violated_rows])

    # Value for Column 2 (for greater_than or equals comparison rules)
    val2 <- if (rule_type %in% c("greater_than", "equals") && exists("col2")) {
      as.character(col2[violated_rows])
    } else {
      rep(NA, length(violated_rows))
    }

    err_df <- data.frame(
      `Rule ID`          = rule_id,
      `Table 1`          = t1_name,
      `VIN`              = vin_col,
      `Row Index`        = violated_rows,
      `Column 1`         = col1_name,
      `Value 1`          = val1,
      `Column 2`         = ifelse(is.na(col2_name), "", col2_name),
      `Value 2`          = val2,
      `Severity`         = severity,
      `Description`      = desc,
      check.names        = FALSE,
      stringsAsFactors   = FALSE
    )
    validation_errors_list[[length(validation_errors_list) + 1]] <- err_df
  }
}

# Step 8: Combine violation data frames and export final Excel report
if (length(validation_errors_list) > 0) {
  validation_report <- do.call(rbind, validation_errors_list)
} else {
  validation_report <- data.frame(Message = "No validation errors found.")
}

# Write final report to Excel
write_xlsx(x = validation_report, path = file.path(Path, "Output", "Validation_Report.xlsx"))
print("Validation execution complete. Report saved to Output/Validation_Report.xlsx")

############################################################################
