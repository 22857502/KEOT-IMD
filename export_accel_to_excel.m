function export_accel_to_excel(result, filename, varargin)
%EXPORT_ACCEL_TO_EXCEL n(예: 24)노드 가속도 응답을 엑셀 파일로 저장
%
%   EXPORT_ACCEL_TO_EXCEL(result, filename, Name,Value,...)
%
%   INPUT
%       result   : simulate_seismic_response_24node()의 출력 struct.
%                  여러 개를 cell로 넘기면 각 result가 별도 시트로 저장됨
%                  (예: {result0, resultUp} -> Initial FE, Updated FE 시트)
%       filename : 저장할 엑셀 파일 경로 (예: 'seismic_accel.xlsx')
%
%   Name-Value (선택)
%       'Unit'       : 'g'(기본), 'm/s2', 또는 'both'(두 단위 모두 각각 시트 저장)
%       'SheetNames' : result가 cell일 때 사용할 시트 이름 cell array
%                      (미지정시 result.label 사용, label도 없으면 Result1, Result2...)
%       'NodePrefix' : 컬럼 헤더 접두어 (기본 'Node_', 예: Node_1, Node_2, ...)
%
%   각 시트 구성: 1열 = Time_s, 2열부터 = Node_1 ... Node_n (가속도)
%
%   OUTPUT: 없음 (filename에 엑셀 파일 저장)

    p = inputParser;
    addParameter(p, 'Unit', 'g');
    addParameter(p, 'SheetNames', {});
    addParameter(p, 'NodePrefix', 'Node_');
    parse(p, varargin{:});

    unitStr    = p.Results.Unit;
    sheetNames = p.Results.SheetNames;
    nodePrefix = p.Results.NodePrefix;

    if ~iscell(result)
        result = {result};
    end
    nR = numel(result);

    if isempty(sheetNames)
        sheetNames = cell(nR,1);
        for r = 1:nR
            if isempty(result{r}.label)
                sheetNames{r} = sprintf('Result%d', r);
            else
                sheetNames{r} = matlab.lang.makeValidName(result{r}.label);
            end
        end
    end

    if numel(sheetNames) ~= nR
        error('export_accel_to_excel:sheetNames', ...
            'SheetNames 개수(%d)가 result 개수(%d)와 일치해야 합니다.', numel(sheetNames), nR);
    end

    switch lower(unitStr)
        case 'g'
            unitsToWrite = {'g'};
        case 'm/s2'
            unitsToWrite = {'m/s2'};
        case 'both'
            unitsToWrite = {'g','m/s2'};
        otherwise
            error('export_accel_to_excel:unit', ...
                'Unit은 ''g'', ''m/s2'', ''both'' 중 하나여야 합니다.');
    end

    for r = 1:nR
        R = result{r};
        nNode = R.n;
        varNames = [{'Time_s'}, arrayfun(@(k) sprintf('%s%d', nodePrefix, k), ...
            1:nNode, 'UniformOutput', false)];

        for u = 1:numel(unitsToWrite)
            if strcmpi(unitsToWrite{u}, 'g')
                dataMat = [R.t, R.accel_g];
                sheetSuffix = '';
                if numel(unitsToWrite) > 1
                    sheetSuffix = '_g';
                end
            else
                dataMat = [R.t, R.accel];
                sheetSuffix = '';
                if numel(unitsToWrite) > 1
                    sheetSuffix = '_ms2';
                end
            end

            T = array2table(dataMat, 'VariableNames', varNames);

            thisSheet = [sheetNames{r} sheetSuffix];
            if length(thisSheet) > 31
                % Excel 시트명 31자 제한
                thisSheet = thisSheet(1:31);
            end

            writetable(T, filename, 'Sheet', thisSheet);
            fprintf('  [export_accel_to_excel] %s : 시트 ''%s''에 %d x %d 저장\n', ...
                filename, thisSheet, size(T,1), size(T,2));
        end
    end
end
