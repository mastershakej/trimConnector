# **Content Manager Power Query Connector**

A custom Power Query connector for **OpenText / Micro Focus Content Manager** (formerly HP TRIM). This connector allows you to pull data directly from the Content Manager **ServiceAPI** into **Microsoft Power BI** and **Excel**.

It is designed to handle common API idiosyncrasies, such as nested object parsing, "twin property" nulls, and ISO date handling.

## **Key Features**

* **Robust Object Parsing:** Automatically extracts readable names from nested objects (e.g., \[Record\] becomes "Document", \[Location\] becomes "John Smith").  
* **Smart Endpoint Selection:** Forces the use of the StreamSearch endpoint for Record searches to ensure rich metadata is returned instead of empty index data.  
* **Date Handling:** Correctly parses ISO 8601 dates with timezones (e.g., 2025-04-06T12:00:00Z) into Power BI DateTime columns.   
* **Location Detail Expansion:** Automatically expands Location objects to include Email, Phone, Organization, and Login details.

## **Installation**

1. **Download the Connector:**  
   * Download the TRIMConnector.mez file from the [Releases](https://github.com/mastershakej/trimConnector/releases/tag/latest) page (or compile it yourself, see below).  
2. **Deploy to Power BI:**  
   * Navigate to your documents folder: C:\\Users\\\[YourName\]\\Documents\\Power BI Desktop\\Custom Connectors.  
   * If this folder does not exist, create it.  
   * Paste the TRIMConnector.mez file into this folder.  
3. **Adjust Security Settings:**  
   * Open Power BI Desktop.  
   * Go to **File** \> **Options and settings** \> **Options**.  
   * Under **Global** \> **Security** \> **Data Extensions**, select:  
     * *"(Not Recommended) Allow any extension to load without validation or warning"*  
   * Click **OK** and **restart Power BI Desktop**.

## **Usage**

1. Open Power BI Desktop.  
2. Click **Get Data** \> **More...**  
3. Search for **"Content Manager"** (usually under the "Other" category).  
4. Click **Connect**.  
5. Enter your ServiceAPI details:  
   * **ServiceAPI URL:** The base URL of your CM ServiceAPI (e.g., http://cm-server.domain.local/ServiceAPI).  
   * **Saved Search:** The **Name** or **Uri** of the Saved Search in Content Manager you wish to run.  
6. Click **OK**.

### **Saved Search Configuration**

For best results, ensure your Saved Search in Content Manager has the columns configured that you wish to see in Power BI. The connector will attempt to fetch these columns plus standard metadata like RecordTitle and RecordNumber.

## **Development & Building**

To modify or build this connector from source:

### **Prerequisites**

* Visual Studio Code  
* [Power Query SDK for VS Code](https://marketplace.visualstudio.com/items?itemName=PowerQuery.vscode-powerquery-sdk)

### **Build Steps**

1. Clone this repository.  
2. Open the folder in VS Code.  
3. Open TRIMConnector.pq.  
4. Run the **Build** task:  
   * Press Ctrl \+ Shift \+ B.  
   * Select **MakePQX.exe compile**.  
5. The compiled extension (.mez) will be generated in the bin\\AnyCPU\\Debug folder.

## **Troubleshooting**

### **"Date Last Updated" is null**

This is a known issue with the CM ServiceAPI where the search index returns a null value while the record metadata contains the date. This connector forces the API to fetch the record metadata via StreamSearch to resolve this. If you still see nulls, ensure your Saved Search is valid.

### **Authentication**

This connector currently supports:

* **Windows Authentication (Default)**  
* **Anonymous/Implicit**  
* **Username/Password** (Basic)

If you receive 401/403 errors, ensure your ServiceAPI is configured to allow the chosen authentication method.
