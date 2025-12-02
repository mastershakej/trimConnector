section TRIMConnector;

PAGE_SIZE = 500;

[DataSource.Kind="TRIMConnector", Publish="TRIMConnector.Publish"]
shared TRIMConnector.Search = Value.ReplaceType(TRIMConnector.Go, TRIMConnector.GoType);

TRIMConnector.Feed = (url as text, schema as type, onePageOnly as logical, options as record, searchString as text) as table => 
    GetAllPagesByNextLink(url, options, schema, onePageOnly, searchString);

RefTrimMainObjectType = type [
    Name = nullable text,       
    Id = nullable text,         
    NameString = nullable text,
    TrimType = nullable text,
    RecordTitle = nullable text,
    RecordNumber = nullable text,
    RecordExternalReference = nullable text,
    DateLastUpdated = nullable text,
    DateCreated = nullable text,
    DateRegistered = nullable text,
    Uri = number
];

RefLocationType = type nullable [
    Name = text,
    NameString = text,
    LocationSortName = text,
    LocationGivenNames = text,
    LocationSurname = text,
    LocationTitle = text, 
    LocationOrganization = text,
    LocationEmailAddress = text,
    LocationPhoneNumber = text,
    LocationMobileNumber = text,
    LocationFaxNumber = text,
    LocationAddress = text,
    LocationLogsInAs = text, 
    LocationAdditionalLogin = text,
    LocationTypeOfLocation = text,
    Uri = number
];

GetSearchClauseDefs =  (baseUrl as text, savedSearchDetails) as table =>  
    let
        Source = Json.Document(Web.Contents(baseUrl & "SearchClauseDef?TrimType=" & savedSearchDetails[trimType] & "&format=json")),
        SearchClauseDefs = Source[SearchClauseDefs],
        convertedToTable = Table.FromList(SearchClauseDefs, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        expandedColumn1 = Table.ExpandRecordColumn(convertedToTable, "Column1", {"BasedOnProperty", "OnlyForType", "InternalName", "Name", "Id", "CanSort", "ObjectTypeParameter", "IsBlocked"}, {"Column1.BasedOnProperty", "Column1.OnlyForType", "Column1.InternalName", "Column1.Name", "Column1.Id", "Column1.CanSort", "Column1.ObjectTypeParameter", "Column1.IsBlocked"}),
        renamedColumns = Table.TransformColumnNames(expandedColumn1, each Text.Replace(_, "Column1."))
    in
        renamedColumns;

GetPropertyDefinitions = (baseUrl as text, savedSearchDetails as record) as table =>  
    let        
        PropertiesAndFields =  GetPropertyList(baseUrl, savedSearchDetails),
        Record = Record.Field(PropertiesAndFields, savedSearchDetails[trimType]),
        convertedToTable = Table.FromList(Record, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        expandedColumn1 = Table.ExpandRecordColumn(convertedToTable, "Column1", {"Id", "PFFormat", "ObjectType", "Property", "IsAField"}, {"Column1.Id", "Column1.PFFormat", "Column1.ObjectType", "Column1.Property", "Column1.IsAField"}),
        filteredRows = Table.SelectRows(expandedColumn1, each [Column1.IsAField] = true or Record.Field([Column1.Property], "IsExposedInSDK") = true)
    in
        filteredRows;

GetPropertyDefinitionsTable = (baseUrl as text, savedSearchDetails as record) as table =>  
    let
        convertedToTable = GetPropertyDefinitions(baseUrl, savedSearchDetails),
        renamedColumns = Table.TransformColumnNames(convertedToTable, each Text.Replace(_, "Column1.")),
        sortedRows = Table.Sort(renamedColumns,{{"IsAField", Order.Ascending}, {"Id", Order.Ascending}}),        
        expandedProperty = Table.ExpandRecordColumn(sortedRows, "Property", {"SearchClauseId"}, {"SearchClauseId"}),
        removedColumns = Table.RemoveColumns(expandedProperty,{"Field"})
    in
        removedColumns;

GetPropertyList = (baseUrl as text, savedSearchDetails as record) as record =>
    let
        searchQuery = [
            q="unkSaved:" & savedSearchDetails[savedSearchId], 
            pageSize="1", 
            excludeCount="true", 
            propertySets="FromSearch", 
            IncludePropertyDefs="true"],
        options = [
            Headers=[#"Accept"="application/json"],
            Query=searchQuery],
        source = Json.Document(Web.Contents(baseUrl & savedSearchDetails[trimType] , options))
    in
        source[PropertiesAndFields];

GetSavedSearchDetails = (baseUrl as text, savedSearchId as text) as record =>
    let
        searchQuery = [
            q=savedSearchId, 
            properties="SavedSearchQueryString,SavedSearchObjectType"],
        options = [
            Headers=[#"Accept"="application/json"],
            Query=searchQuery],
        source = Json.Document(Web.Contents(baseUrl & "SavedSearch/" , options)),
        results = if (source[Results] = null or List.Count(source[Results]) = 0) then
            error Error.Record("Unable to find Saved Search '" & savedSearchId & "'.", "Unable to find Saved Search '" & savedSearchId & "'.") 
            else [
                trimType = source[Results]{0}[SavedSearchObjectType][Value], 
                query = source[Results]{0}[SavedSearchQueryString][Value]]
    in
        results;   

GetVersion = (baseUrl as text) as number =>
    let
        options = [
            Headers=[#"Accept"="application/json"],
            Query=[
                q="all", 
                properties="DatabaseSchemaVersion"]],
        source = Json.Document(Web.Contents(baseUrl & "Database", options))
    in
        source[Results]{0}[DatabaseSchemaVersion][Value];

GetTypeRecord = (baseUrl as text, savedSearchDetails as record) as table => 
    let
        propertyDefs = GetPropertyDefinitions(baseUrl, savedSearchDetails),
        MissingFields = #table(
            {"Column1.Id", "Column1.PFFormat", "Column1.ObjectType", "Column1.Property", "Column1.IsAField"},
            {
                {"DateLastUpdated", "Datetime", "Record", "DateLastUpdated", false}
            }
        ),
        combinedDefs = Table.Distinct(Table.Combine({propertyDefs, MissingFields}), "Column1.Id"),
        locationFilteredRows = Table.SelectRows(combinedDefs, each ( Text.StartsWith([Column1.Id], "LocationOld") = false )),
        addedCustom = Table.AddColumn(locationFilteredRows, "Type", each 
            if List.Contains({"HistoryEventObject","HistoryRelatedObjectUri", "HistoryForObjectUri"}, [Column1.Id]) then
                type nullable number else  
            if [Column1.PFFormat] = "Object" or [Column1.PFFormat] = "Enum" then
                type nullable text else   
            if List.Contains({"Number", "BigNumber", "Decimal", "Currency"}, [Column1.PFFormat]) then
                type nullable number else  
            if [Column1.PFFormat] = "Datetime" then
                type nullable datetime else  
            if [Column1.PFFormat] = "Date" then
                type nullable date else 
            if [Column1.PFFormat] = "Boolean" then
                type nullable logical else                 
            type nullable text
        ),
        addedCustom1 = Table.AddColumn(addedCustom, "Value", each type [pType]),
        renamedColumns = Table.RenameColumns(addedCustom1,{{"Column1.Id", "Name"}}),
        typeTablewithName = Table.SelectColumns(renamedColumns, {"Name", "Type"})
    in
        typeTablewithName;

GetSearchClause = (baseUrl as text, savedSearchDetails as record, propertyId as text) as text =>
    let
        propertyDefs = GetPropertyDefinitionsTable(baseUrl, savedSearchDetails),
        searchClauseDefs = GetSearchClauseDefs(baseUrl, savedSearchDetails),
        searchClause = searchClauseDefs{[BasedOnProperty=propertyId]},
        sortClause = if searchClause <> null and searchClause[CanSort] = true then searchClause[InternalName] else "",
        searchClauseId = if propertyDefs{[Id=propertyId]}[IsAField] = true then propertyId else sortClause
    in
        searchClauseId;

GetSchemaForEntity = (baseUrl as text, savedSearchDetails as record) as type => 
    let 
        schema = Schema.ToTableType(GetTypeRecord(baseUrl, savedSearchDetails))
    in
        schema;

TRIMConnector.GoType = type function (
    baseUrl as (type text meta [
        Documentation.FieldCaption = "ServiceAPI URL",
        Documentation.FieldDescription = "URL to your ServiceAPI URL",
        Documentation.SampleValues = {"http://MyServer/ServiceAPI/"}
    ]),
    savedSearchId as (type text meta [
        Documentation.FieldCaption = "Saved Search name or URI",
        Documentation.FieldDescription = "Saved Search name or URI"
    ]))
    as table meta [    
        Documentation.Name = "Content Manager",
        Documentation.LongDescription = "Query data from Content Manager"       
    ];

TRIMConnector.Go = (baseUrl, savedSearchId as text) as table =>
    let
       ulrWithTrailingSlash = if Text.EndsWith(baseUrl, "/") then baseUrl else baseUrl & "/",
       savedSearchDetails = GetSavedSearchDetails(ulrWithTrailingSlash, savedSearchId) & [savedSearchId = savedSearchId, version = GetVersion(ulrWithTrailingSlash)],
       go = TRIMConnector.View(ulrWithTrailingSlash, savedSearchDetails)
    in
       go;
               
GetPage = (url as text, query as record, schema as type) =>
    let  
        existingColumns = Record.FieldNames(Type.RecordFields(Type.TableRow(schema))), 
        optionsWithPageSize = if Record.HasFields(query, "pageSize") then query else query & [pageSize = Text.From(PAGE_SIZE)],
        options = [
            Headers=[#"Content-Type"="application/json"], 
            Content= Json.FromValue(optionsWithPageSize)
        ],
        source = Json.Document(Web.Contents( url, options)),        
        results = source[Results],
        convertedToTable = Table.FromList(results, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        checkEmpty = if Table.IsEmpty(convertedToTable) then #table(type table[Column1 = [Uri = number]],{}) else convertedToTable,
        expanded = Table.ExpandRecordColumn(checkEmpty, "Column1", existingColumns, existingColumns),
        transformed = List.Transform(existingColumns, each {_, FriendlyRowValues}),
        pageTable = Table.FromRecords(Table.TransformRows(expanded, (row) => Record.TransformFields(row, transformed))),
        hasMoreItems = GetHasMoreItems(source)
    in
        pageTable meta [HasMoreItems = hasMoreItems, LastStart = query[start]?, SearchId = query[id]];

TRIMConnector = [
    TestConnection = (dataSourcePath) => 
         let
            json = Json.Document(dataSourcePath),
            baseUrl = json[baseUrl],
            savedSearchId = json[savedSearchId]
        in
            { "TRIMConnector.Search", baseUrl, savedSearchId },
    Authentication = [
        UsernamePassword = [],
        Windows = [],
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

shared Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            
            (lastPage) => lastPage <> null,     
            (lastPage) => getNextPage(lastPage) 
        ),
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

GetAllPagesByNextLink = (url as text, options as record, schema as type, onePageOnly as logical, searchString as text) as table =>
    Table.GenerateByPage((previous) => 
        let
            newOptions = options & [
                start = if (previous = null) then options[start] else if Value.Metadata(previous)[HasMoreItems] = false then 0 else Value.Metadata(previous)[LastStart]+PAGE_SIZE
                ],
            optionsWithCache = 
                if onePageOnly = true then 
                    newOptions 
                else 
                    newOptions & [id = if (previous = null) then Number.ToText(Number.Random()) else Value.Metadata(previous)[SearchId]], 
            page = 
                if previous <> null and onePageOnly = true then null
                else if (optionsWithCache[start] > 0) then GetPage(url, optionsWithCache, schema) 
                else null
        in
            page
    );

GetHasMoreItems = (response) as logical => Record.FieldOrDefault(response, "HasMoreItems");

TRIMConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = TRIMConnector.Icons,
    SourceTypeImage = TRIMConnector.Icons
];

TRIMConnector.Icons = [
    Icon16 = { Extension.Contents("TRIMConnector16.png"), Extension.Contents("TRIMConnector20.png"), Extension.Contents("TRIMConnector24.png"), Extension.Contents("TRIMConnector32.png") },
    Icon32 = { Extension.Contents("TRIMConnector32.png"), Extension.Contents("TRIMConnector40.png"), Extension.Contents("TRIMConnector48.png"), Extension.Contents("TRIMConnector64.png") }
];

FriendlyRowValues = (val) =>
    let
        colValue = 
            if val = null then null
            else if val is record then
                if Record.HasFields(val, "Name") then val[Name]
                else if Record.HasFields(val, "NameString") then val[NameString]
                else if Record.HasFields(val, "IsTimeClear") then 
                    let 
                        isoString = val[DateTime]?,
                        parsedZone = if isoString <> null then try DateTimeZone.FromText(isoString) otherwise null else null,
                        finalDt = if parsedZone <> null then DateTimeZone.RemoveZone(parsedZone) else null
                    in 
                        finalDt
                else if Record.HasFields(val, "Value") then val[Value]
                else if Record.HasFields(val, "Id") then val[Id]
                else val 
            else
                val
    in
        colValue;

TRIMConnector.View = (baseUrl as text, savedSearchDetails as record) as table =>
    let
        UlrWithTrailingSlash = (state) as text => 
             let
                ulrWithTrailingSlash = if Text.EndsWith(state[Url], "/") then state[Url] else state[Url] & "/"
            in
                ulrWithTrailingSlash,

        CalculateSchema = (state) as type =>
            if (state[Schema]? = null) then
                GetSchemaForEntity(UlrWithTrailingSlash(state), savedSearchDetails)
            else
                state[Schema],

        CalculateExistingColumns = (state) as list =>
            let                    
                currentSchema = CalculateSchema(state),
                rowRecordType = Type.RecordFields(Type.TableRow(currentSchema)),
                existingColumns = Record.FieldNames(rowRecordType)
            in
                existingColumns,

        RefineSchema = (state, columns) as type =>
            let
                currentSchema = CalculateSchema(state),
                rowRecordType = Type.RecordFields(Type.TableRow(currentSchema)),
                existingColumns = CalculateExistingColumns(state),
                columnsToRemove = List.Difference(existingColumns, columns),
                updatedColumns = Record.RemoveFields(rowRecordType, columnsToRemove),
                newSchema = type table (Type.ForRecord(updatedColumns, false))
            in                  
                newSchema,

        CalculateUrl = (state) as text => 
            let
                ulrWithTrailingSlash = UlrWithTrailingSlash(state),
                endpoint = if (savedSearchDetails[trimType] = "Record") then "StreamSearch" else "Search",
                urlWithEntity = Uri.Combine(ulrWithTrailingSlash, endpoint)
            in
                urlWithEntity,

        CalculateCountUrl = (state) as text => 
             let
                ulrWithTrailingSlash = UlrWithTrailingSlash(state),
                urlWithEntity = Uri.Combine(ulrWithTrailingSlash, state[Entity]),
                defaultQueryString = [ resultsOnly = "true", q = savedSearchDetails[query], CountResults="true"],
                encodedQueryString = Uri.BuildQueryString(defaultQueryString),
                finalUrl = urlWithEntity & "?" & encodedQueryString
            in
                finalUrl,

        CalculateOptions = (state) as record => 
            let
                 tmoColumns = Record.FieldNames(Type.RecordFields(RefTrimMainObjectType)),
                 locationColumns = Record.FieldNames(Type.RecordFields(RefLocationType)),                    
                 allProps = List.Distinct(List.Combine({locationColumns, tmoColumns})),
                defaultQueryString = [
                    TrimType=state[Entity],
                    RetrieveLoginIdForLocations="true", 
                    resultsOnly = "true", 
                    q = savedSearchDetails[query], 
                    descendantProperties = Text.Combine(allProps, ",")
                ],
                qsWithTop = 
                    if (state[Top]? <> null) then
                        defaultQueryString & [ #"pageSize" = Number.ToText(if state[Top] = 0 then -1 else state[Top]), #"start" = "1" ]
                    else
                        defaultQueryString,

                qsWithSkip = 
                    if (state[Skip]? <> null) then
                        qsWithTop & [ #"start" = Number.ToText(state[Skip] + 1) ]
                    else
                        qsWithTop,
                
                qsWithSelect = qsWithSkip & [ #"properties" = Text.Combine( List.First(List.RemoveNulls({ state[SelectColumns]?, CalculateExistingColumns(state)})) , ",") ],
                
                qsWithOrderBy = 
                    if (state[OrderBy]? <> null) then
                        qsWithSelect & [ #"sortBy" = state[OrderBy] ]
                    else
                        qsWithSelect
            in
                qsWithOrderBy,

        View = (state as record) => Table.View(#table(null, {}), Diagnostics.WrapHandlers([
            GetType = () => CalculateSchema(state),
            GetRows = () => 
                let                  
                    finalSchema = CalculateSchema(state),
                    finalUrl = CalculateUrl(state),
                    finalOptions = CalculateOptions(state), 
                    optionsWithTop = finalOptions & [start = if state[Skip]? <> null then state[Skip]+1 else 1],
                    result = TRIMConnector.Feed(finalUrl, finalSchema, state[Top]? <> null, optionsWithTop, savedSearchDetails[query]),
                    appliedType = Table.ChangeType(result, finalSchema)
                in
                    appliedType,
            GetRowCount = () as number =>
                let
                    finalUrl = CalculateCountUrl(state),
                    value = TRIMConnector.Atomic(finalUrl)                        
                in
                    value,
            OnTake = (count as number) =>
                let
                    newState = state & [ Top = count ]
                in
                    @View(newState),
            OnSkip = (count as number) =>
                let
                    newState = state & [ Skip = count ]
                in
                    @View(newState),
            OnSelectColumns = (columns as list) =>
                let
                    currentSchema = GetSchemaForEntity(UlrWithTrailingSlash(state), savedSearchDetails),
                    rowRecordType = Type.RecordFields(Type.TableRow(currentSchema)),
                    existingColumns = CalculateExistingColumns(state),
                    columnsToRemove = List.Difference(existingColumns, columns),
                    updatedColumns = Record.RemoveFields(rowRecordType, columnsToRemove),
                    newSchema = RefineSchema(state, columns)
                in
                    @View(state & [ SelectColumns = columns, Schema = newSchema ]),
            OnSort = (order as list) =>
                let
                    sorting = List.Transform(order, (o) => 
                        let
                            column = GetSearchClause(UlrWithTrailingSlash(state), savedSearchDetails, o[Name]),
                            order = o[Order],
                            orderText = if (order = Order.Ascending) then "" else "-"
                        in
                            if column <> "" then column & orderText else null
                    ),
                    orderBy =  Text.Combine(List.RemoveNulls(sorting), ", ")
                in
                    @View(state & [ OrderBy = orderBy ])
        ]))
    in
        View([Url = baseUrl, Entity = savedSearchDetails[trimType]]);

TRIMConnector.Atomic = (url as text) as number =>
    let
        headers = [#"Accept" = "application/json"],
        response = Web.Contents(url, [ Headers = headers ]),
        source = Json.Document(response),       
        fieldVal = source[Count]
    in
        fieldVal;

    Schema.ToTableType = (schema as table) as type =>
        let
            toList = List.Transform(schema[Type], (t) => [Type=t, Optional=false]),
            toRecord = Record.FromList(toList, schema[Name]),
            toType = Type.ForRecord(toRecord, false),
            previousMeta = Value.Metadata(schema)
        in
            type table (toType) meta previousMeta;

Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

Table.ChangeType = Extension.LoadFunction("Table.ChangeType.pqm");
Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = Diagnostics[LogValue];
Diagnostics.LogFailure = Diagnostics[LogFailure];
Diagnostics.WrapHandlers = Diagnostics[WrapHandlers];