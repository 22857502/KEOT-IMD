function [t, ag, dt_orig] = load_ground_motion_elcentro(filename, unit, dtTarget)
%LOAD_GROUND_MOTION_ELCENTRO El-Centro 지진파 엑셀 데이터 로드 및 정리
%
%   [t, ag, dt_orig] = LOAD_GROUND_MOTION_ELCENTRO(filename, unit, dtTarget)
%
%   INPUT
%       filename : El-Centro 엑셀 파일 경로 (예: 'El-centro.xlsx')
%                  1열 = time [s], 2열 = accel
%       unit     : 'g'    -> 9.80665를 곱해 m/s^2로 변환
%                  'm/s2' -> 변환 없음 (기본값)
%       dtTarget : 지정하면 해당 시간간격으로 균일 리샘플링(선형보간).
%                  지정하지 않으면 원본 시간축 그대로 반환.
%
%   OUTPUT
%       t       : n x 1 시간벡터 [s]
%       ag      : n x 1 지반가속도 [m/s^2]
%       dt_orig : 원본 데이터의 시간간격(median) [s]

    if nargin < 2 || isempty(unit)
        unit = 'm/s2';
    end

    if exist(filename, 'file') ~= 2
        error('load_ground_motion_elcentro:fileNotFound', ...
            'El-Centro 파일을 찾을 수 없습니다: %s', filename);
    end

    eq = readmatrix(filename);

    if size(eq,2) < 2
        error('load_ground_motion_elcentro:format', ...
            '%s 파일에서 최소 2개 열(time, accel)이 필요합니다.', filename);
    end

    t_raw  = eq(:,1);
    ag_raw = eq(:,2);

    valid = isfinite(t_raw) & isfinite(ag_raw);
    t_raw  = t_raw(valid);
    ag_raw = ag_raw(valid);

    if isempty(t_raw)
        error('load_ground_motion_elcentro:empty', ...
            '%s에서 유효한 (time, accel) 데이터를 찾지 못했습니다.', filename);
    end

    [t_raw, sortIdx] = sort(t_raw);
    ag_raw = ag_raw(sortIdx);

    dt_orig = median(diff(t_raw));

    switch lower(unit)
        case 'g'
            g0 = 9.80665;
            ag_raw = ag_raw * g0;
        case 'm/s2'
            % 변환 없음
        otherwise
            error('load_ground_motion_elcentro:unit', ...
                'unit은 ''g'' 또는 ''m/s2''여야 합니다.');
    end

    if nargin >= 3 && ~isempty(dtTarget)
        t  = (t_raw(1):dtTarget:t_raw(end)).';
        ag = interp1(t_raw, ag_raw, t, 'linear', 'extrap');
    else
        t  = t_raw;
        ag = ag_raw;
    end
end
