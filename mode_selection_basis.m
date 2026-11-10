% =====================================================================================
% Program : mode_selection_basis.m  (rev.4 - 한두리교 24노드, 배경/SNR 구분 추가)
% Extracts DATA-BASED evidence for choosing how many / which modes to use
% in the EOT sensor selection and IMD covariance dimension.
%
%   (1) EXCITATION  : band power of the UNDAMAGED response around each mode
%                     -> "is this mode actually excited by ambient input?"
%   (2) DAMAGE SENS.: (useDamageConfirmation=true 일 때만) relative band-power
%                     change (undamaged -> damaged) per damage case
%                     -> "does this mode carry damage information?"
%   (3) CUMULATIVE  : running share of total in-band response energy when
%                     modes are added in excitation-strength order
%                     -> "how many modes are enough?"
%
%   NOTE: excitation strength is a MODEL-FREE, defensible primary criterion.
%         Damage sensitivity is CONFIRMATION only (avoid selecting modes
%         using damage data alone -> circularity).
%
%   [REV.4 변경사항] 두 가지 기여도 지표 + SNR 명시
%     - excite%(tot)   : 분모 = 전체대역 밴드파워(배경 포함). 데이터 품질/SNR 관점.
%                        배경이 크면 이 값이 낮아져 "모드로 설명 안 되는 잡음이 많다"를 드러냄.
%     - excite%(modes) : 분모 = 9개 모드 밴드파워 합(배경 제외). 모드 간 상대비교/선정 관점.
%                        누적에너지 곡선(cum_share)과 동일한 기준. 다 더하면 100%.
%     - SNR            : 각 모드 봉우리 평균 PSD / 인접 배경 PSD (배경 대비 몇 배 솟았나).
%                        SNR이 낮은 모드는 상대비율상 포함되더라도 잡음에 묻혀 식별 불안정.
%     - 모드 선정(recommendedModes)은 배경제외 기준(excite%(modes))으로 수행.
%
%   [REV.3 이전 변경사항]
%     - useDamageConfirmation 스위치, 한두리교 24노드/9모드, bw 자동축소,
%       파일 자동탐색, 시간열 fs 자동계산, 놓친 피크 자동탐지 등
%     - load_accel.m, psd_avg.m, bandpow.m 함수가 경로에 있어야 함
% =====================================================================================

clear all; clc; close all;

% ---------------------------------------------------------------------------
% 0. SETTINGS
% ---------------------------------------------------------------------------
fs_fallback = 500;               % 시간열이 없거나 감지 실패 시 사용할 fs [Hz]
useTimeColumnFs = true;          % true: 파일 시간열에서 fs 자동계산 (권장)
N_sensor   = 24;                  % 한두리교 24노드
bw_request = 0.20;                % 요청 half-bandwidth [Hz] (모드간격에 맞춰 자동 축소됨)
energyThreshold = 90;             % 누적에너지 기준 [%]
snrWarnLevel = 3;                 % SNR이 이 값 미만인 모드는 "잡음에 묻힐 수 있음" 경고

useDamageConfirmation = false;    % true : 손상 파일까지 로드해 확인단계 수행
                                   % false: 무손상(실측) 데이터만으로 excitation 기반 선정

% --- mode_freq 소스 선택 ---
% 'manual' : 아래 mode_freq_manual을 그대로 사용 (FE 이론/목표값)
% 'auto'   : 실측 PSD 봉우리를 extract_measured_modes로 자동추출해 mode_freq로 사용
%            (지정↔실측 어긋남, 유령모드, 강한모드 누락 문제를 원천 해결)
modeFreqSource = 'auto';

% (manual일 때) 한두리교 3Hz 이하 실측 9개 모드
% mode_freq_manual = [0.449642 0.646423 0.728461 0.912378 1.008340 ...
%                     1.122340 1.379730 1.539390 1.613280];

% (auto일 때) 자동추출 파라미터
autoBand        = [0.3 3.0];   % 봉우리 탐색대역 [Hz]
autoMinSNR      = 3;           % 이 SNR 미만 봉우리는 제외 (유령모드 배제)
autoMinSep      = 0.05;        % 봉우리 최소간격 [Hz] (중복 병합)
autoMaxModes    = Inf;         % 최대 추출 개수 (Inf=제한없음)
% FE 매칭용: merged 결과의 FE 고유진동수(freqUpHz_all)를 주면 FE 모드번호 자동 매칭
feMergedFile    = 'hangduri_24node_merged_result.mat';

% ---------------------------------------------------------------------------
% 0b. FILE DISCOVERY
% ---------------------------------------------------------------------------
undam_candidates = {'undamage.xlsx', 'undamage.xls', ...
                     'hangduri_ambient.xlsx', 'hangduri_ambient.xls'};   % TODO: 실제 파일명 확인
undam_file = find_existing_file_local(undam_candidates);

if useDamageConfirmation
    dmg_candidates = { ...
        {'hangduri_24node_damage_single_G2center_accel.xlsx'},             'single_G2center'; ...
        {'hangduri_24node_damage_combined_G2center_G3torsion_accel.xlsx'}, 'combined'};

    nd = size(dmg_candidates,1);
    dmg_files = cell(nd,2);
    for c = 1:nd
        dmg_files{c,1} = find_existing_file_local(dmg_candidates{c,1});
        dmg_files{c,2} = dmg_candidates{c,2};
    end
else
    nd = 0;
    dmg_files = cell(0,2);
    fprintf('useDamageConfirmation = false : 손상 데이터 없이 excitation 기반 모드선정만 수행합니다.\n');
end

% ---------------------------------------------------------------------------
% 1. LOAD SIGNALS
% ---------------------------------------------------------------------------
[U, fs_detected] = load_accel(undam_file, N_sensor);   % 1열=시간열 가정, 시간열에서 fs 계산

if useTimeColumnFs && isfinite(fs_detected)
    fs = fs_detected;
    fprintf('>> fs를 시간열에서 자동 계산한 값으로 사용: fs = %.4f Hz\n', fs);
else
    fs = fs_fallback;
    fprintf('>> fs를 fallback 값으로 사용: fs = %.4f Hz (시간열 감지=%.4f)\n', fs, fs_detected);
end
fprintf('Loaded undamaged : %s (%d x %d)\n', undam_file, size(U,1), size(U,2));

D = cell(nd,1);
for c = 1:nd
    D{c} = load_accel(dmg_files{c,1}, N_sensor);
    fprintf('Loaded %-14s : %s (%d x %d)\n', dmg_files{c,2}, dmg_files{c,1}, size(D{c},1), size(D{c},2));
end

L = size(U,1);
for c = 1:nd, L = min(L, size(D{c},1)); end
U = U(1:L,:);
for c = 1:nd, D{c} = D{c}(1:L,:); end

% ---------------------------------------------------------------------------
% 2. PSD (Welch) 1차 계산 — mode_freq 확정 전이므로 넉넉한(가용 최대) window 사용
% ---------------------------------------------------------------------------
dataLenSec = size(U,1) / fs;
maxUsableWindowSec = dataLenSec / 4;   % 최소 4개 구간 평균
windowSec = maxUsableWindowSec;         % 1차: 가용 최대 해상도로

fprintf('\nPSD 1차 window = %.1f s (데이터 %.1f s, 가용최대 기준)\n', windowSec, dataLenSec);

[fU, PU] = psd_avg(U, fs, 'WindowSec', windowSec);
PD = cell(nd,1);
for c = 1:nd, [~, PD{c}] = psd_avg(D{c}, fs, 'WindowSec', windowSec); end

% ---------------------------------------------------------------------------
% 2b. mode_freq 확정 (수동 지정 vs 실측 PSD 봉우리 자동추출)
% ---------------------------------------------------------------------------
FE_mode_map = [];   % auto일 때만 채워짐 (실측봉우리 -> FE 모드번호)
switch lower(modeFreqSource)
    case 'manual'
        mode_freq = mode_freq_manual;
        fprintf('>> mode_freq 소스 = manual (FE 이론/목표값 %d개 사용)\n', numel(mode_freq));

    case 'auto'
        FE_freq_for_match = [];
        if exist(feMergedFile,'file') == 2
            Sfe = load(feMergedFile, 'freqUpHz_all');
            if isfield(Sfe,'freqUpHz_all')
                FE_freq_for_match = Sfe.freqUpHz_all;
                fprintf('>> FE 고유진동수 로드(%s): %d개, 매칭에 사용\n', ...
                    feMergedFile, numel(FE_freq_for_match));
            end
        else
            fprintf('>> (참고) %s 없음 -> FE 모드 매칭 없이 실측 봉우리만 추출\n', feMergedFile);
        end

        [mode_freq, peakInfoAuto] = extract_measured_modes(fU, PU, ...
            'Band', autoBand, 'MinSNR', autoMinSNR, 'MinSeparation', autoMinSep, ...
            'MaxModes', autoMaxModes, 'FE_freq', FE_freq_for_match);

        if isempty(mode_freq)
            error('mode_selection_basis:autoNoModes', ...
                '자동추출로 모드를 찾지 못했습니다. autoMinSNR/autoBand를 조정하거나 manual로 바꾸세요.');
        end
        fprintf('>> mode_freq 소스 = auto (실측 PSD 봉우리 %d개 추출)\n', numel(mode_freq));
        peakInfoAuto = sortrows(peakInfoAuto, 'freq_Hz');   % mode_freq와 열 정렬 맞춤
        FE_mode_map = peakInfoAuto.FE_mode;

    otherwise
        error('mode_selection_basis:modeFreqSource', ...
            'modeFreqSource는 ''manual'' 또는 ''auto''여야 합니다.');
end
nmode = numel(mode_freq);

% ---------------------------------------------------------------------------
% 2c. 모드별 half-bandwidth 자동 조정 (인접 모드와 겹치지 않도록)
% ---------------------------------------------------------------------------
bw_actual = zeros(nmode,1);
for m = 1:nmode
    if m == 1, gapLeft = Inf; else, gapLeft = mode_freq(m) - mode_freq(m-1); end
    if m == nmode, gapRight = Inf; else, gapRight = mode_freq(m+1) - mode_freq(m); end
    maxAllowedBw = 0.45 * min(gapLeft, gapRight);
    bw_actual(m) = min(bw_request, maxAllowedBw);

    if bw_actual(m) < bw_request - 1e-9
        warning('mode_selection_basis:bandOverlap', ...
            'Mode %d (%.4f Hz): 요청 bw=%.3fHz는 인접모드와 겹쳐 bw=%.4fHz로 자동 축소됨.', ...
            m, mode_freq(m), bw_request, bw_actual(m));
    end
end

% ---------------------------------------------------------------------------
% 2d. 필요시 PSD 정밀 재계산 (확정된 bw에 맞는 해상도가 1차보다 더 필요하면)
% ---------------------------------------------------------------------------
targetDf = min(bw_actual) / 5;
neededWindowSec = 1 / targetDf;

if neededWindowSec > windowSec + 1e-9 && neededWindowSec <= maxUsableWindowSec + 1e-9
    windowSec = min(neededWindowSec, maxUsableWindowSec);
    fprintf('PSD 2차 재계산: 확정 bw 기준 목표해상도 df<=%.5fHz -> window=%.1fs\n', ...
        targetDf, windowSec);
    [fU, PU] = psd_avg(U, fs, 'WindowSec', windowSec);
    for c = 1:nd, [~, PD{c}] = psd_avg(D{c}, fs, 'WindowSec', windowSec); end
elseif neededWindowSec > maxUsableWindowSec + 1e-9
    warning('mode_selection_basis:insufficientDataLength', ...
        ['데이터 길이(%.1fs)가 부족해 목표 해상도(%.5fHz)를 만족하지 못합니다. ' ...
         '가장 좁은 밴드 결과는 신뢰도가 낮을 수 있으니, 더 긴 데이터나 bw_request 증가를 고려하세요.'], ...
        dataLenSec, targetDf);
end

% ---------------------------------------------------------------------------
% 3. PER-MODE METRICS
% ---------------------------------------------------------------------------
totalLow  = max(0, min(mode_freq(:) - bw_actual(:)) - 0.05);
totalHigh = min(40, fs/2-1);
tot = bandpow(fU, PU, totalLow, totalHigh);   % 전체대역 밴드파워 (배경 포함)
fprintf('전체 기준대역(tot) 적분범위 = [%.3f, %.3f] Hz (모든 모드밴드를 포함하도록 자동 설정)\n', ...
    totalLow, totalHigh);

exc          = zeros(nmode,1);    % 모드 밴드파워 (봉우리 면적)
excpct_tot   = zeros(nmode,1);    % % (분모 = tot, 배경 포함)
snr_mode     = zeros(nmode,1);    % 봉우리 평균 PSD / 인접 배경 PSD
dmgpct       = zeros(nmode, nd);

for m = 1:nmode
    fc   = mode_freq(m);
    bw_m = bw_actual(m);

    exc(m)      = bandpow(fU, PU, fc-bw_m, fc+bw_m);
    excpct_tot(m) = 100*exc(m)/tot;

    % --- SNR: 봉우리 밴드 평균 PSD vs 인접 배경(밴드 바로 바깥) 평균 PSD ---
    inBand   = fU >= (fc-bw_m)      & fU <= (fc+bw_m);
    sideBand = (fU >= (fc-3*bw_m) & fU < (fc-bw_m)) | ...
               (fU >  (fc+bw_m)   & fU <= (fc+3*bw_m));
    peakLevel = mean(PU(inBand),   'omitnan');
    bgLevel   = median(PU(sideBand),'omitnan');   % 배경은 median으로 robust하게
    if isfinite(bgLevel) && bgLevel > 0
        snr_mode(m) = peakLevel / bgLevel;
    else
        snr_mode(m) = NaN;
    end

    for c = 1:nd
        pc = bandpow(fU, PD{c}, fc-bw_m, fc+bw_m);
        dmgpct(m,c) = 100*(pc - exc(m))/exc(m);
    end
end

% --- 배경 제외(모드끼리) 기준 % : 선정/누적에 사용 ---
excpct_modes = 100 * exc / sum(exc);

% 선정은 배경제외 기준(모드끼리 상대비교)으로 수행
[~, order] = sort(excpct_modes, 'descend');
exc_rank = zeros(nmode,1);
exc_rank(order) = (1:nmode)';

cum_share = cumsum(excpct_modes(order));   % 이미 %라서 합이 100

% ---------------------------------------------------------------------------
% 3b. 누적에너지 임계값을 만족하는 최소 모드 개수/목록 자동 산출
% ---------------------------------------------------------------------------
nNeeded = find(cum_share >= energyThreshold, 1, 'first');
if isempty(nNeeded)
    nNeeded = nmode;
    warning('mode_selection_basis:thresholdNotReached', ...
        '누적에너지가 %.0f%%에 도달하지 못했습니다. 전체 %d개 모드를 사용합니다.', ...
        energyThreshold, nmode);
end
recommendedModes = sort(order(1:nNeeded));

fprintf('\n>> 누적에너지 %.0f%% 기준 최소 모드 개수 = %d\n', energyThreshold, nNeeded);
fprintf('>> 추천 모드(원 번호, 오름차순)   = %s\n', mat2str(recommendedModes));
fprintf('>> 추천 모드 주파수 [Hz]          = %s\n', mat2str(mode_freq(recommendedModes)));
if ~useDamageConfirmation
    fprintf('>> (참고) 현재 useDamageConfirmation=false 이므로 이 선정은 excitation 기준만 반영됨.\n');
    fprintf('   손상 데이터 준비되면 useDamageConfirmation=true로 바꿔 확인단계를 추가하세요.\n');
end

% SNR 낮은 모드 경고
lowSnrIdx = find(snr_mode < snrWarnLevel);
if ~isempty(lowSnrIdx)
    fprintf('>> [주의] SNR<%.0f 인 모드(잡음에 묻힐 수 있음): %s\n', ...
        snrWarnLevel, mat2str(lowSnrIdx(:)'));
end

% ---------------------------------------------------------------------------
% 4. CONSOLE TABLE
% ---------------------------------------------------------------------------
fprintf('\n===== Per-mode selection basis =====\n');
fprintf('excite%%(tot)=배경포함 분모, excite%%(modes)=배경제외(모드끼리), SNR=봉우리/배경\n');
hdr = sprintf('%-5s %-10s %-8s %-13s %-14s %-9s %-9s', ...
    'Mode','freq(Hz)','bw(Hz)','excite%(tot)','excite%(modes)','SNR','excRank');
for c = 1:nd, hdr = [hdr sprintf(' %-13s', ['dmg ' dmg_files{c,2}])]; end %#ok<AGROW>
disp(hdr);
for m = 1:nmode
    line = sprintf('%-5d %-10.4f %-8.4f %-13.6f %-14.2f %-9.2f %-9d', ...
        m, mode_freq(m), bw_actual(m), excpct_tot(m), excpct_modes(m), snr_mode(m), exc_rank(m));
    for c = 1:nd, line = [line sprintf(' %+-13.1f', dmgpct(m,c))]; end %#ok<AGROW>
    disp(line);
end

fprintf('\n===== Cumulative energy share (modes added by excitation rank, 배경제외 기준) =====\n');
fprintf('%-8s %-14s %-14s\n','#modes','added mode','cum share(%)');
for k = 1:nmode
    fprintf('%-8d M%-13d %-14.1f\n', k, order(k), cum_share(k));
end

% ---------------------------------------------------------------------------
% 4b. 진단: 지정 mode_freq vs 실측 PSD의 실제 피크 위치 대조
% ---------------------------------------------------------------------------
fprintf('\n===== 진단: 지정 mode_freq vs 실측 PSD 실제 피크 =====\n');
fprintf('%-5s %-12s %-12s %-12s %-10s\n', ...
    'Mode','지정(Hz)','실제피크(Hz)','오차(Hz)','피크PSD');
searchHalf = 0.10;
for m = 1:nmode
    fc = mode_freq(m);
    sIdx = fU >= (fc - searchHalf) & fU <= (fc + searchHalf);
    if nnz(sIdx) < 2
        fprintf('%-5d %-12.4f %-12s %-12s %-10s\n', m, fc, '(구간부족)','-','-');
        continue;
    end
    fLocal = fU(sIdx);
    PLocal = PU(sIdx);
    [pkVal, pkRel] = max(PLocal);
    fPeak = fLocal(pkRel);
    fprintf('%-5d %-12.4f %-12.4f %+-12.4f %-10.3e\n', ...
        m, fc, fPeak, fPeak - fc, pkVal);
end
fprintf(['해석: "오차(Hz)"가 지정 밴드폭(bw)보다 크면 지정 mode_freq가 실측 피크에서 벗어난 것.\n' ...
         '      이 경우 mode_freq를 실측 PSD 기준으로 다시 잡거나, 실측 OMA 재확인이 필요합니다.\n']);
fprintf('      또한 그림(PSD: undamaged)에서 검은 곡선의 봉우리와 빨간 점선(M1~M9) 위치를 직접 대조하세요.\n');

% ---------------------------------------------------------------------------
% 4c. 진단: mode_freq에 없는데 강하게 나타나는 PSD 피크(놓친 모드 후보) 자동 탐지
% ---------------------------------------------------------------------------
peakSearchBand = [max(0.2, totalLow), min(3.0, totalHigh)];
bandMask = fU >= peakSearchBand(1) & fU <= peakSearchBand(2);
fBand = fU(bandMask);
PBand = PU(bandMask);
peakThreshold = 0.02 * max(PBand);
matchTol = 0.05;

if exist('findpeaks','file') == 2
    [pkVals, pkFreqs] = findpeaks(PBand, fBand, ...
        'MinPeakHeight', peakThreshold, ...
        'MinPeakProminence', 0.5*peakThreshold);

    missedFreqs = [];
    missedVals  = [];
    for i = 1:numel(pkFreqs)
        if all(abs(pkFreqs(i) - mode_freq(:)) > matchTol)
            missedFreqs(end+1,1) = pkFreqs(i); %#ok<AGROW>
            missedVals(end+1,1)  = pkVals(i);  %#ok<AGROW>
        end
    end

    fprintf('\n===== 진단: mode_freq에 없는 강한 PSD 피크 (놓친 모드 후보) =====\n');
    fprintf('탐색대역 = [%.2f, %.2f] Hz, 유의성 기준 = 최대피크의 %.0f%% 이상\n', ...
        peakSearchBand(1), peakSearchBand(2), 100*0.02);
    if isempty(missedFreqs)
        fprintf('  -> 지정한 %d개 모드 외에 유의미한 추가 피크는 발견되지 않았습니다.\n', nmode);
    else
        fprintf('  -> 지정 목록에 없는 강한 피크 %d개 발견 (재검토 권장):\n', numel(missedFreqs));
        fprintf('     %-14s %-14s %-14s\n', '피크주파수(Hz)','피크PSD','최대대비(%)');
        [~, si] = sort(missedVals, 'descend');
        for k = si'
            fprintf('     %-14.4f %-14.3e %-14.1f\n', ...
                missedFreqs(k), missedVals(k), 100*missedVals(k)/max(PBand));
        end
        fprintf(['  해석: 위 피크들이 크기가 크다면 원래 OMA에서 누락된 실제 모드일 수 있습니다.\n' ...
                 '        FE 모드형상/주파수와 대조해 독립모드인지 판단하세요.\n']);
    end
else
    fprintf('\n(참고) findpeaks(Signal Processing Toolbox)가 없어 놓친 모드 자동탐지를 건너뜁니다.\n');
end

% ---------------------------------------------------------------------------
% 5. WRITE CSV / MAT
% ---------------------------------------------------------------------------
T = table((1:nmode)', mode_freq(:), bw_actual(:), excpct_tot, excpct_modes, snr_mode, exc_rank(:), ...
    'VariableNames', {'Mode','freq_Hz','bw_Hz','excite_pct_tot','excite_pct_modes','SNR','exc_rank'});
for c = 1:nd
    T.(sprintf('dmg_%d', c)) = dmgpct(:,c);
end
writetable(T, 'mode_selection_basis.csv');
fprintf('\nWrote mode_selection_basis.csv\n');

save('mode_selection_result.mat', 'mode_freq','bw_actual','exc', ...
    'excpct_tot','excpct_modes','snr_mode','exc_rank', ...
    'dmgpct','cum_share','order','energyThreshold','nNeeded','recommendedModes', ...
    'useDamageConfirmation','modeFreqSource','FE_mode_map');
fprintf('Wrote mode_selection_result.mat (recommendedModes 포함)\n');

% ---------------------------------------------------------------------------
% 6. FIGURES
% ---------------------------------------------------------------------------
figure('Color','w');
bar(1:nmode, [excpct_tot(:), excpct_modes(:)]); grid on;
xlabel('Mode'); ylabel('Excitation band power (%)');
title('Mode excitation strength (undamaged response)');
legend({'% of total (배경포함)','% of modes (배경제외)'}, 'Location','northeast');
set(gca,'XTick',1:nmode);

figure('Color','w');
plot(1:nmode, cum_share, '-o', 'LineWidth', 1.6); grid on;
xlabel('Number of modes (added by excitation rank)');
ylabel('Cumulative energy share (%)');
title('Cumulative Energy Curve');
yline(energyThreshold, 'r--', sprintf('%d%%', energyThreshold));
xline(nNeeded, 'b--', sprintf('n=%d', nNeeded));

figure('Color','w');
bar(1:nmode, snr_mode); grid on;
xlabel('Mode'); ylabel('SNR (peak / background)');
title('Mode SNR (봉우리 대비 배경)');
yline(snrWarnLevel, 'r--', sprintf('SNR=%d', snrWarnLevel));
set(gca,'XTick',1:nmode);

figure('Color','w');
semilogy(fU, PU, 'k-', 'LineWidth', 1.4, 'DisplayName', 'Undamaged'); hold on;
if nd > 0
    clr = lines(nd);
    for c = 1:nd
        semilogy(fU, PD{c}, 'LineWidth', 1.2, 'Color', clr(c,:), ...
                 'DisplayName', dmg_files{c,2});
    end
end
for m = 1:nmode
    xline(mode_freq(m), 'r--', sprintf('M%d', m), ...
          'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
end
grid on;
xlabel('Frequency (Hz)'); ylabel('PSD (avg over sensors)');
title('PSD: undamaged (+ damaged if available)'); legend('Location','northeast'); hold off;

if nd > 0
    figure('Color','w');
    bar(1:nmode, dmgpct); grid on;
    xlabel('Mode'); ylabel('Band-power change vs undamaged (%)');
    title('Damage sensitivity per mode');
    set(gca,'XTick',1:nmode);
    legend(dmg_files(:,2), 'Location','northeast');
else
    fprintf('\n(참고) useDamageConfirmation=false : damage-sensitivity 그림은 생략됨.\n');
end

% ---------------------------------------------------------------------------
% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
% ---------------------------------------------------------------------------
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 5/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [5/9] 모드 선정 완료  ->  mode_selection_result.mat (recommendedModes)\n');
fprintf('  >> 다음 실행: EOT_xlsx.m\n');
fprintf('     (EOT 최적 센서 선정 — 그림 11, 정보곡선 det(KE))\n');
fprintf('====================================================\n');

% ---------------------------------------------------------------------------
% LOCAL FUNCTION
% ---------------------------------------------------------------------------
function filename = find_existing_file_local(candidates)
    filename = '';
    for i = 1:numel(candidates)
        if exist(candidates{i}, 'file') == 2
            filename = candidates{i};
            return;
        end
    end

    listing = [dir('*.xlsx'); dir('*.xls')];
    fprintf('\n다음 후보 파일을 찾을 수 없습니다: %s\n', strjoin(candidates, ', '));

    if isempty(listing)
        error('find_existing_file_local:notFound', ...
            '현재 폴더(%s)에 xlsx/xls 파일 자체가 없습니다. cd로 올바른 폴더로 이동했는지 확인하세요.', ...
            pwd);
    end

    fprintf('현재 폴더(%s)에서 발견된 엑셀 파일 목록:\n', pwd);
    for i = 1:numel(listing)
        fprintf('  %2d) %s\n', i, listing(i).name);
    end

    [selFile, selPath] = uigetfile({'*.xlsx;*.xls','Excel files (*.xlsx,*.xls)'}, ...
        '해당하는 데이터 파일을 선택하세요');

    if isequal(selFile, 0)
        error('find_existing_file_local:userCancelled', ...
            ['파일 선택이 취소되었습니다. 위 목록을 참고해 코드 상단의 후보 목록(candidates)에 ' ...
             '실제 파일명을 직접 추가한 뒤 다시 실행하세요.']);
    end

    filename = fullfile(selPath, selFile);
    fprintf('선택된 파일: %s\n', filename);
end
