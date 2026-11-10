%% run_IMD_handuri_fixed.m   (재작성)
% =====================================================================================
% 한두리교 - 계측잡음 기반 고정 baseline으로 IMD 손상 판정 (EOT 8센서)
%
% [연구 논리]
%   - 공용 실교량은 검증된 무손상(pristine)이 없으므로, 실계측으로 업데이트한
%     상태를 "기준상태(reference)"로 가정한다. (Updated_FE)
%   - 손상은 FE에서 ΔK,ΔM을 반영해 만든 손상 상태공간 응답으로 모사한다. (Cable4Break)
%   - 관리선(UCL)은 Heo & Kim(2014) 식(5~7): CL=mean(IMD), UCL=CL+3σ (α=3, 99.7%).
%   - 결정론적 시뮬레이션은 반복해도 응답이 동일하므로, Heo&Kim의 "반복 가진"이
%     만든 무손상 변동을 '계측 잡음'으로 재현한다.
%       * 잡음: 0~fcut(8) Hz 대역제한 백색, σ=2.9e-4 g (실측 무손상 PSD 잡음저에서 산정)
%       * 무손상-무손상(잡음차) 분포에서 m0,R0,CL0,UCL0 고정 -> 손상 IMD를 판정
%
% [주의] 지진응답은 계측잡음 대비 SNR이 매우 높아(≈51 dB) UCL이 타이트하다.
%        따라서 케이블 파단은 뚜렷이 검출되며, baseline 변동을 계측잡음만으로
%        잡은 것은 낙관적(민감) 평가임을 결과 해석/논문에 명시할 것.
%
% [의존] imd_compute.m, build_noise_baseline.m, bandlimited_noise.m
% =====================================================================================

clear; clc; close all;
rng(7);   % 재현성

%% 0. 설정
undam_file  = 'hangduri_24node_seismic_accel.xlsx';   undam_sheet = 'Updated_FE';  % 기준상태
dam_file    = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet  = 'Cable4Break'; % 손상

eot_sensors = [4 7 9 11 14 16 19 23];   % EOT 최적 8센서 (FE node 번호)

fs = 100;  rms_win_sec = 40;  rms_start_sec = 5;    % El-Centro dt=0.01 -> 100 Hz

sigma_noise = 2.9e-4;   % 계측 잡음저 [g] (실측 무손상 PSD 고주파 평탄부에서 산정)
fcut        = 8;        % 잡음 대역제한 [Hz] (실측 Nyquist)
N_base      = 40;       % 무손상 반복(잡음 실현) 수 (Heo & Kim 40회에 대응)

compareFull = true;     % Full(24) 참고 비교

%% 1. 의존성 점검
for fn = {'imd_compute','build_noise_baseline','bandlimited_noise'}
    if exist(fn{1},'file') ~= 2
        error('%s.m 을 MATLAB 경로에 두세요.', fn{1});
    end
end
if max(eot_sensors) > 24 || min(eot_sensors) < 1
    error('eot_sensors는 1~24 범위여야 합니다: %s', mat2str(eot_sensors));
end

%% 2. 데이터 로드 (g, 24노드, Time열 제외)
Xu = read_accel_sheet(undam_file, undam_sheet, 24);   % 기준상태 무손상
Xd = read_accel_sheet(dam_file,   dam_sheet,   24);   % 손상(케이블 4개 파단)
T  = min(size(Xu,1), size(Xd,1));
Xu = Xu(1:T,:);  Xd = Xd(1:T,:);
fprintf('기준상태: %s[%s], 손상: %s[%s]\n', undam_file, undam_sheet, dam_file, dam_sheet);
fprintf('T=%d, fs=%dHz, sigma_noise=%.2e g(0~%dHz), N_base=%d\n\n', T, fs, sigma_noise, fcut, N_base);

%% 3. EOT(8) : 계측잡음 baseline -> 손상 IMD 판정
baseE = build_noise_baseline(Xu, eot_sensors, fs, sigma_noise, fcut, N_base);
rE    = imd_compute(Xu, Xd, eot_sensors, fs, rms_win_sec, rms_start_sec, baseE);

fprintf('================= IMD 관리차트 (EOT %d센서) =================\n', numel(eot_sensors));
fprintf('무손상 baseline(계측잡음)에서 고정: CL0=%.4f, UCL0=%.4f, LCL0=%.4f (α=3, 99.7%%)\n', ...
    baseE.CL0, baseE.UCL0, baseE.LCL0);
fprintf('cond(R0)=%.3e\n', rE.condR);
verdictE = '미검출';  if 100*rE.over_UCL >= 1.0, verdictE = '손상 감지'; end
fprintf('손상 [%s]: IMD max=%.2f, over_UCL=%.2f%%, RMS_RMD=%.4f, DR_RMD=%.2f%%  -> %s\n\n', ...
    dam_sheet, max(rE.imd), 100*rE.over_UCL, rE.RMS_RMD, rE.DR_RMD, verdictE);

%% 4. Full(24) 참고 비교
if compareFull
    baseF = build_noise_baseline(Xu, 1:24, fs, sigma_noise, fcut, N_base);
    rF    = imd_compute(Xu, Xd, 1:24, fs, rms_win_sec, rms_start_sec, baseF);
    fprintf('[참고] Full(24): CL0=%.4f, UCL0=%.4f, cond(R0)=%.3e, over_UCL=%.2f%%, DR_RMD=%.2f%%\n\n', ...
        baseF.CL0, baseF.UCL0, rF.condR, 100*rF.over_UCL, rF.DR_RMD);
end

%% 5. 플롯 A - 무손상 관리차트 (Fig.7 스타일, EOT)
figure('Color','w','Name','Fig.7 baseline control chart (EOT)'); hold on; grid on;
imd0plot = baseE.imd0(1:min(T, numel(baseE.imd0)));      % 무손상 IMD (대표 1구간)
plot((0:numel(imd0plot)-1)/fs, imd0plot, 'Color',[0.2 0.4 0.9], 'DisplayName','Un-damage IMD');
yline(baseE.CL0 , '-',  'CL0',  'Color',[0 0.5 0],   'LineWidth',1.2);
yline(baseE.UCL0, '--', 'UCL0', 'Color',[0.85 0 0],  'LineWidth',1.4);
yline(baseE.LCL0, '--', 'LCL0', 'Color',[0.85 0 0],  'LineWidth',1.0);
xlabel('Time (s)'); ylabel('IMD');
title('Baseline control chart (measurement-noise, EOT 8)');
legend('Location','northeast'); hold off; drawnow;
saveas(gcf, 'IMD_handuri_baseline_Fig7.png');

%% 6. 플롯 B - 손상 판정 관리차트 (Fig.8 스타일, EOT)
figure('Color','w','Name','Fig.8 damage control chart (EOT)'); hold on; grid on;
xoff = 0;
plot((0:numel(imd0plot)-1)+xoff, imd0plot, 'Color',[0.4 0.4 0.4], 'DisplayName','Un-damage');
xoff = xoff + numel(imd0plot);
xline(xoff, ':', 'Color',[0.6 0.6 0.6], 'HandleVisibility','off');
plot((0:numel(rE.imd)-1)+xoff, rE.imd, 'Color',[0.15 0.15 0.15], 'DisplayName',dam_sheet);
yline(baseE.CL0 , '-',  'CL0',  'Color',[0 0.5 0],  'LineWidth',1.2);
yline(baseE.UCL0, '--', 'UCL0', 'Color',[0.85 0 0], 'LineWidth',1.5);
ylabel('IMD'); xlabel('sample');
title(sprintf('Damage control chart vs fixed baseline (EOT 8, DR_{RMD}=%.1f%%)', rE.DR_RMD));
legend('Location','northeast'); set(gca,'YScale','log'); hold off; drawnow;
saveas(gcf, 'IMD_handuri_damage_Fig8.png');

%% 7. 결과 저장
Case      = {dam_sheet};
CL        = baseE.CL0;
UCL       = baseE.UCL0;
over_UCL  = 100*rE.over_UCL;
RMS_RMD   = rE.RMS_RMD;
DR_RMD    = rE.DR_RMD;
IMD_max   = max(rE.imd);
n_over    = sum(rE.imd > baseE.UCL0);
n_total   = numel(rE.imd);
Tsum = table(Case, CL, UCL, over_UCL, RMS_RMD, DR_RMD, IMD_max, n_over, n_total);
writetable(Tsum, 'IMD_handuri_summary.xlsx');
save('IMD_handuri_result.mat', 'baseE','rE','eot_sensors','fs', ...
     'rms_win_sec','rms_start_sec','sigma_noise','fcut','N_base');

fprintf('===== 요약 =====\n'); disp(Tsum);
fprintf('저장: IMD_handuri_result.mat, IMD_handuri_summary.xlsx, IMD_handuri_baseline_Fig7.png, IMD_handuri_damage_Fig8.png\n');
fprintf('Done.\n');

%% ===== LOCAL FUNCTION =====
function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    try
        Traw = readtable(filename, 'Sheet', sheet);
    catch
        error('시트 ''%s'' 를 못 찾음: %s', sheet, filename);
    end
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));            % 전부 NaN인 열 제거
    if size(M,2) >= nNode+1
        X = M(:, end-nNode+1:end);         % 마지막 nNode열 = 노드 (앞 Time열 제외)
    elseif size(M,2) == nNode
        X = M;
    else
        error('%s(시트 %s): 열 수(%d)가 nNode(%d)와 안 맞음.', filename, sheet, size(M,2), nNode);
    end
    X(~isfinite(X)) = 0;
end
