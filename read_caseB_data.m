function data = read_caseB_data(dataFile)
% read_caseB_data
% Read and preprocess the Case B market dataset for the grid-scale battery
% arbitrage coursework.
%
% INPUT:
%   dataFile   - path to CSV file
%
% OUTPUT:
%   data       - struct containing cleaned time series and metadata
%
% Returned fields:
%   data.rawTable                  raw imported table
%   data.time                      datetime vector
%   data.price_mwh                 day-ahead price [GBP/MWh]
%   data.price_kwh                 day-ahead price [GBP/kWh]
%   data.imbalance_price_mwh       imbalance price [GBP/MWh] (if available)
%   data.imbalance_price_kwh       imbalance price [GBP/kWh] (if available)
%   data.ancillary_price_mw_h      ancillary availability [GBP/MW/h] (if available)
%   data.carbon_intensity          carbon intensity [kg/kWh] (if available)
%   data.N                         number of time steps
%   data.dt                        time step [h]
%   data.timeStepHoursVector       time difference vector [h]
%   data.columnMap                 detected column names
%
% Notes:
% - Base case primarily uses day-ahead price.
% - Other columns are retained for possible extensions.
% - Prices are converted from GBP/MWh to GBP/kWh by dividing by 1000.

    %% 1. Basic file checks
    if nargin < 1 || isempty(dataFile)
        error('read_caseB_data:MissingInput', ...
            'Input dataFile is required.');
    end

    if ~isfile(dataFile)
        error('read_caseB_data:FileNotFound', ...
            'The file "%s" was not found.', dataFile);
    end

    %% 2. Import table
    opts = detectImportOptions(dataFile);

% For compatibility with different MATLAB versions,
% avoid using unsupported setvaropts options globally.
try
    rawTable = readtable(dataFile, opts);
catch
    rawTable = readtable(dataFile);
end

    if isempty(rawTable) || height(rawTable) == 0
        error('read_caseB_data:EmptyFile', ...
            'The file "%s" contains no readable data rows.', dataFile);
    end

    originalNames = rawTable.Properties.VariableNames;
    normalizedNames = normalizeNames(originalNames);

    %% 3. Detect important columns
    colTime = findColumn(normalizedNames, ...
        {'timestamp', 'time', 'datetime', 'date', 'settlementperiodstart', 'periodstart'});

    colDayAhead = findColumn(normalizedNames, ...
        {'dayaheadpricegbppermwh', 'dayaheadprice', 'day_ahead_price_gbp_per_mwh', ...
         'pricegbppermwh', 'marketprice', 'price'});

    colImbalance = findColumn(normalizedNames, ...
        {'imbalancepricegbppermwh', 'imbalanceprice', 'imbalance_price_gbp_per_mwh'});

    colAncillary = findColumn(normalizedNames, ...
        {'ancillaryavailabilitygbppermwperh', 'ancillaryavailability', ...
         'ancillary_price', 'ancillary'});

    colCarbon = findColumn(normalizedNames, ...
        {'carbonintensitykgperkwh', 'carbonintensity', ...
         'carbon_intensity_kg_per_kwh_optional', 'carbon'});

    if isempty(colTime)
        error('read_caseB_data:MissingTimeColumn', ...
            ['Could not identify a timestamp column. ', ...
             'Please check the CSV header names.']);
    end

    if isempty(colDayAhead)
        error('read_caseB_data:MissingPriceColumn', ...
            ['Could not identify the day-ahead price column. ', ...
             'Please check the CSV header names.']);
    end

    %% 4. Parse timestamp column
    timeRaw = rawTable{:, colTime};

    try
        time = convertToDatetime(timeRaw);
    catch ME
        error('read_caseB_data:TimeParseError', ...
            'Failed to parse the timestamp column into datetime values.\n%s', ME.message);
    end

    %% 5. Read numeric columns
    price_mwh = convertToNumeric(rawTable{:, colDayAhead}, originalNames{colDayAhead});

    imbalance_price_mwh = [];
    if ~isempty(colImbalance)
        imbalance_price_mwh = convertToNumeric(rawTable{:, colImbalance}, originalNames{colImbalance});
    end

    ancillary_price_mw_h = [];
    if ~isempty(colAncillary)
        ancillary_price_mw_h = convertToNumeric(rawTable{:, colAncillary}, originalNames{colAncillary});
    end

    carbon_intensity = [];
    if ~isempty(colCarbon)
        carbon_intensity = convertToNumeric(rawTable{:, colCarbon}, originalNames{colCarbon});
    end

    %% 6. Remove rows with missing essential values
    essentialMask = ~(isnat(time) | isnan(price_mwh));

    removedEssential = sum(~essentialMask);
    if removedEssential > 0
        warning('read_caseB_data:RemovedMissingRows', ...
            'Removed %d rows with missing timestamp or day-ahead price.', removedEssential);
    end

    rawTable = rawTable(essentialMask, :);
    time = time(essentialMask);
    price_mwh = price_mwh(essentialMask);

    if ~isempty(imbalance_price_mwh)
        imbalance_price_mwh = imbalance_price_mwh(essentialMask);
    end
    if ~isempty(ancillary_price_mw_h)
        ancillary_price_mw_h = ancillary_price_mw_h(essentialMask);
    end
    if ~isempty(carbon_intensity)
        carbon_intensity = carbon_intensity(essentialMask);
    end

    %% 7. Sort by time if needed
    [time, sortIdx] = sort(time);
    rawTable = rawTable(sortIdx, :);
    price_mwh = price_mwh(sortIdx);

    if ~isempty(imbalance_price_mwh)
        imbalance_price_mwh = imbalance_price_mwh(sortIdx);
    end
    if ~isempty(ancillary_price_mw_h)
        ancillary_price_mw_h = ancillary_price_mw_h(sortIdx);
    end
    if ~isempty(carbon_intensity)
        carbon_intensity = carbon_intensity(sortIdx);
    end

    %% 8. Check duplicate timestamps
    if numel(unique(time)) < numel(time)
        warning('read_caseB_data:DuplicateTimestamps', ...
            ['Duplicate timestamps were detected. ', ...
             'The optimisation may still run, but this should be checked.']);
    end

    %% 9. Time step calculation
    if numel(time) < 2
        error('read_caseB_data:TooFewRows', ...
            'At least two valid rows are required to estimate the time step.');
    end

    dtVec = hours(diff(time));

    % Use the median as the representative time step
    dt = median(dtVec);

    if any(~isfinite(dtVec))
        error('read_caseB_data:InvalidTimeStep', ...
            'Non-finite time-step values detected after parsing timestamps.');
    end

    % Check whether the data are roughly hourly
    tol = 1e-6;
    irregularMask = abs(dtVec - dt) > tol;
    numIrregular = sum(irregularMask);

    if numIrregular > 0
        warning('read_caseB_data:IrregularTimeStep', ...
            ['Detected %d irregular time-step intervals. ', ...
             'Median time step %.6f h will be used.'], numIrregular, dt);
    end

    if abs(dt - 1.0) > 1e-3
        warning('read_caseB_data:NonHourlyData', ...
            ['The detected median time step is %.6f h, not exactly 1 h. ', ...
             'Please confirm this matches the coursework dataset.'], dt);
    end

    %% 10. Unit conversion
    % GBP/MWh -> GBP/kWh
    price_kwh = price_mwh / 1000;

    imbalance_price_kwh = [];
    if ~isempty(imbalance_price_mwh)
        imbalance_price_kwh = imbalance_price_mwh / 1000;
    end

    %% 11. Build output struct
    data = struct();

    data.rawTable = rawTable;
    data.time = time;
    data.price_mwh = price_mwh;
    data.price_kwh = price_kwh;

    data.imbalance_price_mwh = imbalance_price_mwh;
    data.imbalance_price_kwh = imbalance_price_kwh;

    data.ancillary_price_mw_h = ancillary_price_mw_h;
    data.carbon_intensity = carbon_intensity;

    data.N = numel(time);
    data.dt = dt;
    data.timeStepHoursVector = dtVec;

    data.columnMap = struct();
    data.columnMap.time = originalNames{colTime};
    data.columnMap.dayAhead = originalNames{colDayAhead};

    if ~isempty(colImbalance)
        data.columnMap.imbalance = originalNames{colImbalance};
    else
        data.columnMap.imbalance = '';
    end

    if ~isempty(colAncillary)
        data.columnMap.ancillary = originalNames{colAncillary};
    else
        data.columnMap.ancillary = '';
    end

    if ~isempty(colCarbon)
        data.columnMap.carbon = originalNames{colCarbon};
    else
        data.columnMap.carbon = '';
    end

    %% 12. Final summary printout
    fprintf('\n--- Data import summary ---\n');
    fprintf('File: %s\n', dataFile);
    fprintf('Detected timestamp column: %s\n', data.columnMap.time);
    fprintf('Detected day-ahead price column: %s\n', data.columnMap.dayAhead);
    if ~isempty(data.columnMap.imbalance)
        fprintf('Detected imbalance price column: %s\n', data.columnMap.imbalance);
    end
    if ~isempty(data.columnMap.ancillary)
        fprintf('Detected ancillary column: %s\n', data.columnMap.ancillary);
    end
    if ~isempty(data.columnMap.carbon)
        fprintf('Detected carbon column: %s\n', data.columnMap.carbon);
    end
    fprintf('Number of usable rows: %d\n', data.N);
    fprintf('Median time step: %.6f h\n', data.dt);
    fprintf('Day-ahead price range: [%.4f, %.4f] GBP/MWh\n', ...
        min(data.price_mwh), max(data.price_mwh));
    fprintf('Converted price range: [%.6f, %.6f] GBP/kWh\n', ...
        min(data.price_kwh), max(data.price_kwh));
    fprintf('---------------------------\n\n');
end


%% ===== Helper functions =====

function normalized = normalizeNames(names)
% Convert variable names to lowercase alphanumeric-only strings
    normalized = cell(size(names));
    for i = 1:numel(names)
        s = lower(string(names{i}));
        s = regexprep(s, '[^a-z0-9]', '');
        normalized{i} = char(s);
    end
end

function idx = findColumn(normalizedNames, candidateNames)
% Return the first matching column index, or [] if none found
    idx = [];
    for k = 1:numel(candidateNames)
        target = lower(candidateNames{k});
        target = regexprep(target, '[^a-z0-9]', '');
        match = find(strcmp(normalizedNames, target), 1, 'first');
        if ~isempty(match)
            idx = match;
            return;
        end
    end
end

function dt = convertToDatetime(x)
% Robust conversion of a timestamp column to datetime
    if isdatetime(x)
        dt = x;
        return;
    end

    if iscell(x) || isstring(x) || ischar(x) || iscategorical(x)
        xStr = string(x);

        % First try automatic parsing
        try
            dt = datetime(xStr);
            return;
        catch
        end

        % Try some common formats
        commonFormats = { ...
            'yyyy-MM-dd HH:mm:ss', ...
            'yyyy-MM-dd HH:mm', ...
            'dd/MM/yyyy HH:mm:ss', ...
            'dd/MM/yyyy HH:mm', ...
            'MM/dd/yyyy HH:mm:ss', ...
            'MM/dd/yyyy HH:mm', ...
            'yyyy/MM/dd HH:mm:ss', ...
            'yyyy/MM/dd HH:mm', ...
            'dd-MMM-yyyy HH:mm:ss', ...
            'dd-MMM-yyyy HH:mm'};

        for i = 1:numel(commonFormats)
            try
                dt = datetime(xStr, 'InputFormat', commonFormats{i});
                return;
            catch
            end
        end

        error('Could not parse text timestamps with the tested formats.');
    end

    if isnumeric(x)
        % Sometimes timestamps can be Excel serial date numbers
        try
            dt = datetime(x, 'ConvertFrom', 'excel');
            return;
        catch
            error('Numeric timestamp column could not be interpreted as Excel datetime.');
        end
    end

    error('Unsupported timestamp column type.');
end

function num = convertToNumeric(x, varName)
% Convert a column into numeric values safely
    if isnumeric(x)
        num = double(x);
        return;
    end

    if islogical(x)
        num = double(x);
        return;
    end

    if iscell(x) || isstring(x) || ischar(x) || iscategorical(x)
        num = str2double(string(x));
        return;
    end

    error('Column "%s" could not be converted to numeric.', varName);
end