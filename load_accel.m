function [X, fs_detected, t_col] = load_accel(filename, N_sensor, varargin)
%LOAD_ACCEL 가속도 계측 파일(xlsx/xls) 로드 - 헤더 행 자동감지 + 시간열 기반 fs 계산
%
%   [X, fs_detected, t_col] = LOAD_ACCEL(filename, N_sensor, Name,Value,...)
%
%   undamage.xlsx처럼 헤더 1줄 + [시간열 + S1..Sn] 컬럼인 파일과,
%   DSC 익스포트(예: 251030_C4_.xls)처럼 헤더가 여러 줄/불규칙한 파일을
%   모두 처리하기 위해, 첫 숫자 데이터가 시작되는 행을 자동으로 찾습니다.
%
%   Name-Value (선택)
%       'HeaderRows' : 헤더 행 수를 직접 지정 (지정시 자동감지 건너뜀)
%       'Columns'    : 사용할 (센서)컬럼 인덱스를 직접 지정
%                      (기본: 숫자데이터 중 마지막 N_sensor개 컬럼 자동선택)
%       'TimeColumn' : 시간열의 컬럼 인덱스 (기본 1 = 첫 번째 열).
%                      []로 지정하면 시간열이 없다고 보고 fs_detected=NaN 반환.
%
%   OUTPUT
%       X           : nt x N_sensor 가속도 행렬 (시간열 제외)
%       fs_detected : 시간열에서 계산한 샘플링 주파수 [Hz]
%                     = 1 / median(diff(시간열)). 시간열이 없으면 NaN.
%       t_col       : 시간열 벡터 (nt x 1). 없으면 빈 배열.
%
%   주의: 시간열 단위가 '초'가 아니라면(예: ms) fs_detected가 배율만큼 달라집니다.
%         콘솔에 출력되는 fs_detected 값이 상식적인지(예: 500Hz 근처) 반드시 확인하세요.

    p = inputParser;
    addParameter(p, 'HeaderRows', []);
    addParameter(p, 'Columns', []);
    addParameter(p, 'TimeColumn', 1);
    parse(p, varargin{:});

    headerRows = p.Results.HeaderRows;
    cols       = p.Results.Columns;
    timeCol    = p.Results.TimeColumn;

    if exist(filename, 'file') ~= 2
        error('load_accel:fileNotFound', '파일을 찾을 수 없습니다: %s', filename);
    end

    raw = readcell(filename);

    if isempty(headerRows)
        headerRows = detect_header_rows_local(raw, N_sensor);
        fprintf('  [load_accel] %s : 헤더 %d행 자동감지됨\n', filename, headerRows);
    end

    if headerRows >= size(raw,1)
        error('load_accel:allHeader', ...
            '%s: 감지된 헤더 행(%d)이 전체 행 수(%d)보다 많거나 같습니다.', ...
            filename, headerRows, size(raw,1));
    end

    dataRaw = raw(headerRows+1:end, :);

    numMat = nan(size(dataRaw));

    isNumCell = cellfun(@(x) isnumeric(x) && isscalar(x), dataRaw);
    numMat(isNumCell) = cell2mat(dataRaw(isNumCell));

    isTxtCell = cellfun(@(x) ischar(x) || isstring(x), dataRaw);
    if any(isTxtCell(:))
        txtIdx = find(isTxtCell);
        for k = 1:numel(txtIdx)
            v = str2double(dataRaw{txtIdx(k)});
            if isfinite(v)
                numMat(txtIdx(k)) = v;
            end
        end
    end

    numMat = numMat(~all(isnan(numMat),2), :);
    numMat = numMat(:, ~all(isnan(numMat),1));

    % --- 시간열 기반 fs 계산 (센서열 선택 전에 원본 numMat 기준으로) ---
    fs_detected = NaN;
    t_col = [];
    if ~isempty(timeCol) && timeCol >= 1 && timeCol <= size(numMat,2)
        t_col = numMat(:, timeCol);
        dt_vec = diff(t_col);
        dt_med = median(dt_vec, 'omitnan');
        if isfinite(dt_med) && dt_med > 0
            fs_detected = 1 / dt_med;
            fprintf('  [load_accel] 시간열(%d열)에서 계산한 dt=%.6g, fs=%.4f Hz\n', ...
                timeCol, dt_med, fs_detected);
            % 시간 간격 일관성 체크
            if std(dt_vec, 'omitnan') / dt_med > 0.01
                warning('load_accel:nonUniformTime', ...
                    '시간열 간격이 균일하지 않습니다 (상대표준편차 %.2f%%). fs가 부정확할 수 있습니다.', ...
                    100*std(dt_vec,'omitnan')/dt_med);
            end
        else
            warning('load_accel:badTimeColumn', ...
                '시간열(%d열)에서 유효한 dt를 계산하지 못했습니다. fs_detected=NaN.', timeCol);
        end
    end

    if isempty(cols)
        if size(numMat,2) < N_sensor
            error('load_accel:notEnoughCols', ...
                '%s: 유효 숫자 컬럼이 %d개뿐입니다 (N_sensor=%d 필요). ''Columns''를 직접 지정하세요.', ...
                filename, size(numMat,2), N_sensor);
        end
        cols = (size(numMat,2)-N_sensor+1) : size(numMat,2);
    end

    X = numMat(:, cols);
    X(~isfinite(X)) = 0;

    fprintf('  [load_accel] %s : %d x %d 추출 (센서컬럼 %s)\n', ...
        filename, size(X,1), size(X,2), mat2str(cols));
end

function headerRows = detect_header_rows_local(raw, N_sensor)
    nRows = size(raw,1);
    headerRows = 0;
    for r = 1:nRows
        rowVals = raw(r,:);
        isNum = cellfun(@(x) isnumeric(x) && isscalar(x) && ~isnan(x), rowVals);
        if sum(isNum) >= N_sensor
            headerRows = r-1;
            return;
        end
    end
    warning('load_accel:headerDetectFail', ...
        '헤더 자동감지 실패 (숫자데이터 %d개 이상인 행을 찾지 못함). headerRows=0으로 처리합니다.', N_sensor);
    headerRows = 0;
end
