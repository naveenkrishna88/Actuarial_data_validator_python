# Excel-lence Data Validator 🚀

Welcome! This tool is an automated data validation engine for actuarial and insurance data. 

We use **Google Gemini AI** to understand your raw data and suggest rules, and then a fast **Python engine** checks your data against those rules to find any errors. This README will guide you step-by-step on how to run it.

---

## 🌟 How It Works

Here is a simple map of what the code does:
```
Input Data (.xlsx) ──► Schema Generator (AI) ──► Data Cleaning ──► Rules Generator (AI) ──► Rules Engine (Python) ──► Output Report (.xlsx)
```

1. **Schema Generator**: The AI looks at your raw data and creates a "blueprint" of what your data looks like (`Output/Data_Schema.xlsx`).
2. **Data Cleaning**: The code automatically cleans up messy dates (like Excel's `44629`) and numbers.
3. **Rules Generator**: The AI writes out logical rules for your data and saves them in `Output/Validation_Rules.xlsx`. *(Note: You can open this file and tweak the rules before running the next step!)*
4. **Rules Engine**: The Python script checks your data against the rules.
5. **Report Generation**: The code generates a detailed error log for you in `Output/Validation_Report.xlsx`.

---

## 🛠️ What Kind of Rules Can It Check?

| Rule Type | What it does | 
| :--- | :--- |
| **`missing`** | Flags any blank or NA values. | 
| **`unique`** | Flags duplicate entries where there should only be one (like an ID). |
| **`positive`** | Flags any numbers that are 0 or negative. | 
| **`range`** | Flags values that are too high or too low. | 
| **`greater_than`** | Checks if one column is larger than another. | 
| **`equals`** | Checks if two columns match perfectly. | 
| **`exists`** | Checks if an ID from one table actually exists in another table. | 
| **`allowed_values`** | Flags text that isn't in an approved list (e.g., status must be "Open" or "Closed"). | 

---

## 🚀 Getting Started in Google Colab

Since we are running this in Google Colab, you don't need to install Python on your computer. Just follow these steps!

### Step 1: Get the Code and Data Ready
1. Since this is a public repository, you can simply download the `Codes/data_validator.ipynb` file (or recreate it using `vibe_coding_prompts.txt`) and open it in [Google Colab](https://colab.research.google.com/).
2. Once the notebook is open in Colab, click the **folder icon** on the left sidebar to open the Files panel.
3. **Upload your data**: Click the upload button in the Files panel and select your input files (`Claims data.xlsx` and `Sales data.xlsx`). *Note: These files are temporarily uploaded to the Colab runtime environment and will be deleted when you close the session.*

### Step 2: Set Up Your API Keys in Colab
1. On the left sidebar of Colab, click the **key icon** (Secrets).
2. Add a new secret:
   - **Name**: `GOOGLE_API_KEY` (or `GEMINI_API_KEY`)
   - **Value**: *(Paste your Gemini API key here)*
   - **Important**: Toggle the switch to grant the notebook access to this secret.
3. Add another secret:
   - **Name**: `GEMINI_MODEL`
   - **Value**: `gemini-3.5-flash-lite` (or whichever model you are using)
   - Toggle the notebook access switch for this one too.

### Step 3: Run the Pipeline!
1. In the notebook, you might see a cell that installs packages (like `pandas`, `agno`, etc.). Run it!
2. Run the notebook **cell by cell** using the Play button on the left of each cell (or press `Shift + Enter`).
3. Make sure the notebook is looking for your files in the base directory (e.g., `./Claims data.xlsx`), since we uploaded them directly to the Colab runtime.

---

## 📊 Where Are My Results?

Once the notebook finishes running, refresh the **folder icon** (Files panel) on the left sidebar. You will see your output files ready to download:

1. **`Data_Schema.xlsx`**: Details about the data types and descriptions for all your columns.
2. **`Validation_Rules.xlsx`**: The rules the AI generated. 
3. **`Validation_Report.xlsx`**: Your final error log! It will tell you exactly which rows failed, the VIN, what the bad value was, and why it failed.

---

## 🎓 Vibe Coding Training

We are using this project to conduct a **vibe coding training**! 

If you are participating, your goal is to recreate the pipeline using the provided AI prompts. If you ever get stuck, struggle, or face any issues while following the prompts, you can refer to the `Codes/data_validator.ipynb` file. It contains the final, working code and serves as a helpful reference to see exactly how the implementation should look!