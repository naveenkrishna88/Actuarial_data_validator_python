import os
import pandas as pd
import numpy as np
import json
import re
from pydantic import BaseModel, Field
from typing import Literal, Optional, List
from agno.agent import Agent
from agno.models.google import Gemini

# -------------------------------------------------------------------------
# Step 1: Initial setup, Models, and Helper Functions and Data Schema generator
# -------------------------------------------------------------------------

# Environment path setup to locate Input/ and Output/ directories
Path_env = os.environ.get("Excel_lence_Path", ".")

# ################################ Models ####################################

class Column_str_describer_AI_output(BaseModel):
    File_name: str = Field(..., description="Name of the target dataset.", alias="File name")
    Column_name: str = Field(..., description="Exact name of the column as present in the dataset.", alias="Column name")
    Data_type: str = Field(..., description="Inferred statistical/R data type.", alias="Data type")
    Description: str = Field(..., description="Elaborate business and technical description. Explain column meaning, potential relationship to other columns, and key validation conditions needed downstream.")

Column_str_describer_AI = Agent(
    model=Gemini(id="gemini-2.5-flash"), # Using gemini-2.5-flash as default, can be modified to gemini-3.1-flash-lite if natively supported in the env.
    system_prompt="""
    You are an expert insurance data architect analyzing datasets for ABC General Insurance Company.
    For each attached dataset (e.g. vehicle sales, warranty claims):
    1. Inspect all columns, data types, sample values, and statistical distributions.
    2. Determine nullability, primary key constraints, and allowable domains/ranges.
    3. Formulate exhaustive column descriptions focusing on business context and inter-table/intra-table relationships (e.g., cross-column comparisons, foreign key lookups between sales and claims).
    """,
    response_model=List[Column_str_describer_AI_output]
)

class Validation_rules_AI_output(BaseModel):
    Rule_ID: str = Field(..., description="Unique identifier for the rule e.g. R001, R002.", alias="Rule ID")
    Table_1: str = Field(..., description="Primary dataset to validate.", alias="Table 1")
    Column_1: str = Field(..., description="Primary column in Table 1 being validated.", alias="Column 1")
    Rule_type: str = Field(..., description="Category of the data validation rule.", alias="Rule type")
    Table_2: Optional[str] = Field(None, description="Secondary/reference dataset for cross-table rules (e.g. sales_data). Leave empty/None for intra-table rules.", alias="Table 2")
    Column_2: Optional[str] = Field(None, description="Secondary column in Table 1 (or Table 2) for 'greater_than', 'equals', or 'exists' rules. Leave empty/None if not applicable.", alias="Column 2")
    Parameter: Optional[str] = Field(None, description="Required parameter. For 'allowed_values': comma-separated categories. For 'range': min and max values ('min, max'). Leave empty/None for others.")
    Severity: str = Field(..., description="Severity level if the rule fails.")
    Description: str = Field(..., description="Detailed explanation of what this rule validates and why.")

Validation_rules_AI = Agent(
    model=Gemini(id="gemini-2.5-flash"),
    system_prompt="""
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

    Do NOT stop early. You MUST generate as many executable rules logically possible across all columns and relationships.
    """,
    response_model=List[Validation_rules_AI_output]
)

# ################################ Functions #################################

def Date_converter_fxn(date_col_to_fix):
    def convert(val):
        if pd.isna(val) or str(val).strip() == "":
            return pd.NaT
        val_str = str(val).strip()
        if len(val_str) == 5 and val_str.isdigit():
            return pd.to_datetime('1899-12-30') + pd.to_timedelta(int(val_str), unit='D')
        else:
            return pd.to_datetime(val_str, errors='coerce', dayfirst=True)
    return date_col_to_fix.apply(convert)

# ################################# Validator functions ######################

def lookup_ref_column(key1, ref_key2, ref_target_col):
    mapping = dict(zip(ref_key2, ref_target_col))
    return key1.map(mapping)

def validate_missing(col1):
    return col1.isna() | (col1.astype(str).str.strip() == "") | (col1.astype(str).str.lower() == "nan")

def validate_unique(col1):
    return col1.duplicated(keep='first')

def validate_positive(col1):
    col1_num = pd.to_numeric(col1, errors='coerce')
    return col1.notna() & (col1_num <= 0)

def validate_range(col1, min_val=-float('inf'), max_val=float('inf')):
    col1_num = pd.to_numeric(col1, errors='coerce')
    return col1.notna() & ((col1_num < min_val) | (col1_num > max_val))

def validate_greater_than(col1, col2):
    valid_mask = col1.notna() & col2.notna()
    violation = col1 <= col2
    return valid_mask & violation

def validate_equals(col1, col2):
    valid_mask = col1.notna() & col2.notna()
    violation = col1 != col2
    return valid_mask & violation

def validate_exists(col1, ref_col):
    return col1.notna() & (~col1.isin(ref_col.dropna()))

def validate_allowed_values(col1, allowed_set):
    clean_col1 = col1.astype(str).str.strip()
    clean_allowed = [str(x).strip() for x in allowed_set]
    return col1.notna() & (~clean_col1.isin(clean_allowed))

validator_tools = {
    "lookup_ref": lookup_ref_column,
    "missing": validate_missing,
    "unique": validate_unique,
    "positive": validate_positive,
    "range": validate_range,
    "greater_than": validate_greater_than,
    "equals": validate_equals,
    "exists": validate_exists,
    "allowed_values": validate_allowed_values
}

# ################################ Data Schema generator #####################

if __name__ == "__main__":
    sales_path = os.path.join(Path_env, "Input", "EV_Vehicle_Sales_Data_500.xlsx")
    claims_path = os.path.join(Path_env, "Input", "EV_Warranty_Claims_Synthetic_Flawed_150-1.xlsx")
    
    sales_data_raw = pd.read_excel(sales_path)
    claims_data_raw = pd.read_excel(claims_path)
    print("Excel files loaded successfully")

    question = (
        "The attached are 2 data tables from ABC insurance company.\n"
        "Sales refers to all the vehicle sales made in the year,\n"
        "Claims refers to all the claims made in the year\n\n"
        f"Sales sample data: \n{sales_data_raw.head(50).to_string()}\n\n"
        f"Claims sample data: \n{claims_data_raw.head(50).to_string()}\n\n"
        f"Sales structure: \n{sales_data_raw.dtypes.to_string()}\n\n"
        f"Claims structure: \n{claims_data_raw.dtypes.to_string()}\n"
    )

    response_schema = Column_str_describer_AI.run(question)
    
    response_DF = pd.DataFrame([item.model_dump(by_alias=True) for item in response_schema.content])
    
    os.makedirs(os.path.join(Path_env, "Output"), exist_ok=True)
    schema_path = os.path.join(Path_env, "Output", "Data_Schema.xlsx")
    response_DF.to_excel(schema_path, index=False)
    print("Data schema generated and saved successfully. Please review them carefully before proceeding.")

    # -------------------------------------------------------------------------
    # Step 2: Data cleaning & Validation rules generator
    # -------------------------------------------------------------------------

    Data_schema = pd.read_excel(schema_path)
    
    sales_data = sales_data_raw.copy()
    claims_data = claims_data_raw.copy()
    
    our_datasets = {"sales_data": sales_data, "claims_data": claims_data}
    
    for i, row in Data_schema.iterrows():
        col_type = row['Data type']
        file_name = row['File name']
        col_name = row['Column name']
        
        if col_type == "Date":
            our_datasets[file_name][col_name] = Date_converter_fxn(our_datasets[file_name][col_name])
            
        if col_type == "Number":
            our_datasets[file_name][col_name] = pd.to_numeric(our_datasets[file_name][col_name], errors='coerce')

    print("Data cleaning complete")

    # Validation rules generator
    rules_question = (
        "Here is the verified data schema with descriptions for the datasets:\n"
        f"{Data_schema.to_json(orient='records', indent=2)}\n\n"
        f"Sales sample data:\n{sales_data.head(50).to_string()}\n\n"
        f"Claims sample data:\n{claims_data.head(50).to_string()}\n\n"
    )

    response_rules = Validation_rules_AI.run(rules_question)
    
    validation_rules_DF = pd.DataFrame([item.model_dump(by_alias=True) for item in response_rules.content])
    
    rules_path = os.path.join(Path_env, "Output", "Validation_Rules.xlsx")
    validation_rules_DF.to_excel(rules_path, index=False)
    print("Validation rules generated and saved successfully. Please review them carefully before proceeding.")

    # -------------------------------------------------------------------------
    # Step 3: Validation rules engine
    # -------------------------------------------------------------------------

    validation_report_list = []
    validation_rules_to_run = pd.read_excel(rules_path)

    for i, rule in validation_rules_to_run.iterrows():
        rule_id   = rule.get('Rule ID')
        t1_name   = rule.get('Table 1')
        col1_name = rule.get('Column 1')
        rule_type = rule.get('Rule type')
        t2_name   = rule.get('Table 2')
        col2_name = rule.get('Column 2')
        param     = rule.get('Parameter')
        severity  = rule.get('Severity')
        desc      = rule.get('Description')
        
        df1  = our_datasets[t1_name]
        col1 = df1[col1_name]
        
        violation_mask = pd.Series([False] * len(df1), index=df1.index)
        col2 = None
        
        if rule_type == "missing":
            violation_mask = validator_tools["missing"](col1)
        elif rule_type == "unique":
            violation_mask = validator_tools["unique"](col1)
        elif rule_type == "positive":
            violation_mask = validator_tools["positive"](col1)
        elif rule_type == "allowed_values":
            if pd.notna(param):
                allowed_set = [x.strip() for x in str(param).split(",")]
            else:
                allowed_set = []
            violation_mask = validator_tools["allowed_values"](col1, allowed_set)
        elif rule_type == "range":
            if pd.notna(param):
                num_params = [float(x) for x in re.findall(r"-?\d+\.?\d*", str(param))]
                min_v = num_params[0] if len(num_params) >= 1 else -float('inf')
                max_v = num_params[1] if len(num_params) >= 2 else float('inf')
            else:
                min_v, max_v = -float('inf'), float('inf')
            violation_mask = validator_tools["range"](col1, min_val=min_v, max_val=max_v)
        elif rule_type == "exists":
            ref_vec = our_datasets[t2_name][col2_name]
            violation_mask = validator_tools["exists"](col1, ref_vec)
        elif rule_type in ["greater_than", "equals"]:
            if pd.notna(t2_name) and str(t2_name).strip() != "":
                key1 = df1[col1_name]
                t2_key2 = our_datasets[t2_name][col1_name]
                t2_target = our_datasets[t2_name][col2_name]
                col2 = validator_tools["lookup_ref"](key1, t2_key2, t2_target)
            else:
                col2 = df1[col2_name]
                
            if rule_type == "greater_than":
                violation_mask = validator_tools["greater_than"](col1, col2)
            elif rule_type == "equals":
                violation_mask = validator_tools["equals"](col1, col2)

        violated_rows = df1.index[violation_mask].tolist()
        
        if len(violated_rows) > 0:
            vin_col = df1['VIN'].iloc[violated_rows].astype(str).tolist() if "VIN" in df1.columns else [pd.NA]*len(violated_rows)
            val1 = col1.iloc[violated_rows].astype(str).tolist()
            
            if rule_type in ["greater_than", "equals"] and col2 is not None:
                val2 = col2.iloc[violated_rows].astype(str).tolist()
            else:
                val2 = [pd.NA]*len(violated_rows)
                
            for idx, r_idx in enumerate(violated_rows):
                validation_report_list.append({
                    'Rule ID': rule_id,
                    'Table 1': t1_name,
                    'VIN': vin_col[idx],
                    'Row Index': r_idx + 1, 
                    'Column 1': col1_name,
                    'Value 1': val1[idx],
                    'Column 2': col2_name if pd.notna(col2_name) else "",
                    'Value 2': val2[idx],
                    'Severity': severity,
                    'Description': desc
                })

    if len(validation_report_list) == 0:
        validation_report = pd.DataFrame([{"Message": "No validation errors found."}])
    else:
        validation_report = pd.DataFrame(validation_report_list)

    report_path = os.path.join(Path_env, "Output", "Validation_Report.xlsx")
    validation_report.to_excel(report_path, index=False)
    print("Validation execution complete. Report saved to Output/Validation_Report.xlsx")