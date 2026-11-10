function [peakFreq, peakInfo] = extract_measured_modes(fU, PU, varargin)
%EXTRACT_MEASURED_MODES 실측 PSD에서 유의미한 모드 봉우리를 자동 추출
%   (+ 선택적으로 FE 고유진동수와 매칭)
%
%   [peakFreq, peakInfo] = EXTRACT_MEASURED_MODES(fU, PU, Name,Value,...)
%
%   지정된 mode_freq(이론/FE 목표값)에 의존하지 않고, 실측 PSD 자체의
%   봉우리를 findpeaks로 뽑아 "실측에서 실제로 잘 잡히는 모드"를 정의한다.
%   모드 5,9처럼 지정 위치에 봉우리가 없는 유령 모드가 애초에 배제되고,
%   2.156Hz처럼 강한데 목록에 없던 봉우리가 자동 포함된다.
%
%   INPUT
%       fU, PU : psd_avg() 등에서 얻은 주파수벡터, 채널평균 PSD
%
%   Name-Value (선택)
%       'Band'         : 봉우리 탐색 주파수 대역 [f_low f_high] (기본 [0.3 3.0])
%       'MinPromRatio' : 최소 prominence 비율 (대역 최대PSD 대비, 기본 0.03)
%       'MinHeightRatio': 최소 높이 비율 (대역 최대PSD 대비, 기본 0.02)
%       'MinSeparation': 봉우리 간 최소 간격 [Hz] (기본 0.05). 이보다 가까운
%                        봉우리는 더 강한 것 하나로 병합됨(모드 2,3 중복 방지)
%       'MinSNR'       : 최소 SNR (봉우리/인접배경, 기본 3). 이 미만은 제외
%       'MaxModes'     : 최대 추출 개수 (기본 Inf). 강도순 상위 N개만
%       'FE_freq'      : FE 고유진동수 벡터 [Hz]. 주면 각 실측봉우리에
%                        가장 가까운 FE 모드번호를 매칭해 peakInfo에 기록
%       'FE_matchTol'  : FE 매칭 허용오차 [Hz] (기본 0.1). 이보다 멀면 매칭 실패(NaN)
%
%   OUTPUT
%       peakFreq : 추출된 봉우리 주파수 [Hz] (오름차순 정렬)
%       peakInfo : 상세 테이블 (freq, psd, prominence, snr, prom_pct,
%                                FE_mode, FE_freq, FE_err) — 강도순
%
%   요구사항: Signal Processing Toolbox (findpeaks)

    p = inputParser;
    addParameter(p, 'Band', [0.3 3.0]);
    addParameter(p, 'MinPromRatio', 0.03);
    addParameter(p, 'MinHeightRatio', 0.02);
    addParameter(p, 'MinSeparation', 0.05);
    addParameter(p, 'MinSNR', 3);
    addParameter(p, 'MaxModes', Inf);
    addParameter(p, 'FE_freq', []);
    addParameter(p, 'FE_matchTol', 0.1);
    parse(p, varargin{:});

    band        = p.Results.Band;
    minPromR    = p.Results.MinPromRatio;
    minHeightR  = p.Results.MinHeightRatio;
    minSep      = p.Results.MinSeparation;
    minSNR      = p.Results.MinSNR;
    maxModes    = p.Results.MaxModes;
    FE_freq     = p.Results.FE_freq;
    matchTol    = p.Results.FE_matchTol;

    if exist('findpeaks','file') ~= 2
        error('extract_measured_modes:noFindpeaks', ...
            'findpeaks(Signal Processing Toolbox)가 필요합니다.');
    end

    fU = fU(:); PU = PU(:);
    mask = fU >= band(1) & fU <= band(2);
    fB = fU(mask);
    PB = PU(mask);

    if numel(fB) < 3
        error('extract_measured_modes:emptyBand', ...
            '탐색대역 [%.2f %.2f]에 PSD 포인트가 부족합니다.', band(1), band(2));
    end

    maxP = max(PB);
    df = median(diff(fB));
    minSepBins = max(1, round(minSep/df));

    % 1) 후보 봉우리 추출
    [pk, loc, ~, prom] = findpeaks(PB, ...
        'MinPeakHeight', minHeightR*maxP, ...
        'MinPeakProminence', minPromR*maxP, ...
        'MinPeakDistance', minSepBins);
    pkFreq = fB(loc);

    if isempty(pkFreq)
        warning('extract_measured_modes:noPeaks', ...
            '기준을 만족하는 봉우리가 없습니다. 기준(MinProm/Height/SNR)을 완화하세요.');
        peakFreq = [];
        peakInfo = table();
        return;
    end

    % 2) 각 봉우리 SNR 계산 (봉우리 ±1bin 평균 / 인접 배경 median)
    snr = zeros(numel(pkFreq),1);
    for i = 1:numel(pkFreq)
        fc = pkFreq(i);
        halfW = max(2*df, minSep/2);
        inB   = fU >= (fc-halfW) & fU <= (fc+halfW);
        sideB = (fU >= (fc-3*halfW) & fU < (fc-halfW)) | ...
                (fU >  (fc+halfW)   & fU <= (fc+3*halfW));
        pkLvl = mean(PU(inB), 'omitnan');
        bgLvl = median(PU(sideB), 'omitnan');
        if isfinite(bgLvl) && bgLvl > 0
            snr(i) = pkLvl/bgLvl;
        else
            snr(i) = NaN;
        end
    end

    % 3) SNR 기준 필터
    keep = snr >= minSNR;
    pkFreq = pkFreq(keep); pk = pk(keep); prom = prom(keep); snr = snr(keep);

    if isempty(pkFreq)
        warning('extract_measured_modes:allBelowSNR', ...
            '모든 봉우리가 MinSNR=%.1f 미만입니다.', minSNR);
        peakFreq = [];
        peakInfo = table();
        return;
    end

    % 4) 강도(PSD)순 정렬 후 MaxModes 제한
    [~, si] = sort(pk, 'descend');
    pkFreq = pkFreq(si); pk = pk(si); prom = prom(si); snr = snr(si);
    if isfinite(maxModes) && numel(pkFreq) > maxModes
        pkFreq = pkFreq(1:maxModes); pk = pk(1:maxModes);
        prom = prom(1:maxModes); snr = snr(1:maxModes);
    end

    % 5) FE 고유진동수 매칭 (선택)
    nP = numel(pkFreq);
    FE_mode = nan(nP,1); FE_f = nan(nP,1); FE_err = nan(nP,1);
    if ~isempty(FE_freq)
        FE_freq = FE_freq(:);
        for i = 1:nP
            [dmin, idx] = min(abs(FE_freq - pkFreq(i)));
            if dmin <= matchTol
                FE_mode(i) = idx;
                FE_f(i)    = FE_freq(idx);
                FE_err(i)  = pkFreq(i) - FE_freq(idx);
            end
        end
    end

    prom_pct = 100*prom/maxP;

    peakInfo = table(pkFreq, pk, prom, prom_pct, snr, FE_mode, FE_f, FE_err, ...
        'VariableNames', {'freq_Hz','psd','prominence','prom_pct','SNR', ...
                          'FE_mode','FE_freq','FE_err'});

    % peakFreq는 오름차순으로 반환 (mode_freq로 바로 쓰기 좋게)
    peakFreq = sort(pkFreq(:))';

    % 콘솔 요약
    fprintf('\n[extract_measured_modes] 추출된 실측 모드 %d개 (강도순):\n', nP);
    disp(peakInfo);
    if ~isempty(FE_freq)
        nMatched = sum(~isnan(FE_mode));
        fprintf('  FE 매칭 성공: %d/%d (허용오차 %.3fHz 이내)\n', nMatched, nP, matchTol);
        if nMatched < nP
            fprintf('  [주의] 매칭 실패한 봉우리는 FE에 대응 모드가 없음 -> EOT shape 확보 불가.\n');
        end
    end
end
