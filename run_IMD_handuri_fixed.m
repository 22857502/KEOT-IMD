%% run_IMD_handuri_fixed.m   [원상복귀: 자기참조 IMD, EOT(8) vs Full(24) 비교]
% =====================================================================================
% 한두리교 - 무손상(Updated_FE) 대비 손상(Cable4Break) 가속도의 IMD를 EOT 8센서와
% Full 24센서에서 각각 계산하고, 두 IMD 시계열을 한 그림에 겹쳐 비교한다.
%
%   IMD = imd_compute(...)  (자기참조 모드: Delta_x = Xu - Xd 에서 m,R,UCL 산정)
%     UCL = mean(IMD) + 3*sigma  (alpha=3, 99.7%)
%     RMS = 강진구간(rms_start~+rms_win) IMD의 RMS
%
% [의존] imd_compute.m
% =====================================================================================

clear; clc; close all;

%% 0. 설정
undam_file  = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';  % 무손상 기준
dam_file    = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet  = 'Cable4Break'; % 손상

eot_sensors = [4 7 9 11 14 16 19 23];   % EOT 최적 8센서 (FE node 번호)
fs = 100;  rms_win_sec = 40;  rms_start_sec = 5;    % El-Centro dt=0.01 -> 100 Hz

%% 1. 의존성 점검
if exist('imd_compute','file') ~= 2
    error('imd_compute.m 을 경로에 두세요.');
end

%% 2. 데이터 로드 (g, 24노드, Time열 제외)
Xu = read_accel_sheet(undam_file, undam_sheet, 24);
Xd = read_accel_sheet(dam_file,   dam_sheet,   24);
T  = min(size(Xu,1), size(Xd,1));
Xu = Xu(1:T,:);  Xd = Xd(1:T,:);
fprintf('무손상: %s[%s], 손상: %s[%s], T=%d, fs=%dHz\n\n', undam_file, undam_sheet, dam_file, dam_sheet, T, fs);

%% 3. IMD (자기참조) - EOT(8), Full(24)
rE = imd_compute(Xu, Xd, eot_sensors, fs, rms_win_sec, rms_start_sec);   % EOT
rF = imd_compute(Xu, Xd, 1:24,        fs, rms_win_sec, rms_start_sec);   % Full

fprintf('%-10s %-9s %-9s %-11s %-11s\n','set','UCL','RMS','over_UCL[%]','cond(R)');
fprintf('%-10s %-9.3f %-9.3f %-11.2f %-11.3e\n','EOT(8)',  rE.UCL, rE.RMS, 100*rE.over_UCL, rE.condR);
fprintf('%-10s %-9.3f %-9.3f %-11.2f %-11.3e\n','Full(24)',rF.UCL, rF.RMS, 100*rF.over_UCL, rF.condR);

%% 4. 비교 그림 (Full 뒤, EOT 앞 - 채움영역)
figure('Color','w','Position',[100 100 720 400]); hold on; grid on;
tt = (0:numel(rF.imd)-1)/fs;
cEOT = [0.16 0.47 0.84];  cFull = [0.92 0.41 0.20];

fill([tt fliplr(tt)], [rF.imd' zeros(1,numel(rF.imd))], cFull, 'EdgeColor',cFull, ...
    'FaceAlpha',1, 'DisplayName', sprintf('Full(24) (RMS=%.3f, over UCL=%.2f%%)', rF.RMS, 100*rF.over_UCL));
fill([tt fliplr(tt)], [rE.imd' zeros(1,numel(rE.imd))], cEOT, 'EdgeColor',cEOT, ...
    'FaceAlpha',1, 'DisplayName', sprintf('EOT (RMS=%.3f, over UCL=%.2f%%)', rE.RMS, 100*rE.over_UCL));

yline(rF.UCL, '--', sprintf('Full UCL=%.2f', rF.UCL), 'Color',cFull, 'LineWidth',1.2, 'LabelHorizontalAlignment','right', 'HandleVisibility','off');
yline(rE.UCL, '--', sprintf('EOT UCL=%.2f',  rE.UCL), 'Color',cEOT,  'LineWidth',1.2, 'LabelHorizontalAlignment','right', 'HandleVisibility','off');

xlabel('Time (s)'); ylabel('IMD');
legend('Location','northeast','AutoUpdate','off');   % 범례 오른쪽 상단 고정
ylim([0 max(rF.UCL, max(rF.imd))*1.05]);
box on;                                              % 외벽선(상자) 4면 표시
set(gca, 'Layer', 'top', 'XColor', 'k', 'YColor', 'k');  % 축선/외벽선을 채움 위에 검정으로
hold off; drawnow;
saveas(gcf, 'IMD_handuri_cable4break.png');

%% 5. 결과 저장 (plot_EOT_vs_Full_comparison_fixed.m 호환 컬럼명)
Set          = {'EOT'; 'Full'};
condR        = [rE.condR;   rF.condR];
over_UCL_pct = [100*rE.over_UCL; 100*rF.over_UCL];
RMS          = [rE.RMS;     rF.RMS];
IMD_max      = [max(rE.imd); max(rF.imd)];
UCL          = [rE.UCL;     rF.UCL];
Tsum = table(Set, condR, over_UCL_pct, RMS, IMD_max, UCL);
writetable(Tsum, 'IMD_handuri_summary.xlsx');
save('IMD_handuri_result.mat', 'rE','rF','eot_sensors','fs','rms_win_sec','rms_start_sec');

fprintf('\n===== 요약 =====\n'); disp(Tsum);
fprintf('저장: IMD_handuri_result.mat, IMD_handuri_summary.xlsx, IMD_handuri_cable4break.png\n');
fprintf('Done.\n');

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 7/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [7/9] IMD 손상 판정 완료  ->  IMD_handuri_summary.xlsx (그림 15)\n');
fprintf('  >> 다음 실행: plot_EOT_vs_Full_comparison_fixed.m\n');
fprintf('     (EOT vs Full 감지성능·공분산 조건수 비교 — 그림 17)\n');
fprintf('====================================================\n');

%% ===== LOCAL FUNCTION =====
function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    try
        Traw = readtable(filename, 'Sheet', sheet);
    catch
        error('시트 ''%s'' 를 못 찾음: %s', sheet, filename);
    end
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));
    if size(M,2) >= nNode+1
        X = M(:, end-nNode+1:end);
    elseif size(M,2) == nNode
        X = M;
    else
        error('%s(시트 %s): 열 수(%d)가 nNode(%d)와 안 맞음.', filename, sheet, size(M,2), nNode);
    end
    X(~isfinite(X)) = 0;
end
