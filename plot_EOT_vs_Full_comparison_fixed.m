%% plot_EOT_vs_Full_comparison_fixed.m
% =====================================================================================
% EOT(8) vs Full(24) IMD 비교 그래프
%
% [변경점] 하드코딩 값(구 오염 데이터 기반: RMS=3.509 등)은 폐기.
%   run_IMD_handuri_fixed.m가 만든 IMD_handuri_summary.xlsx에서 자동 로드한다.
%   (수정 트윈 파이프라인으로 다시 계산한 값이라야 유효)
%
% [지표]
%   cond(R)  : 공분산 조건수. 낮을수록 R^-1 안정 -> 공정 비교지표.
%   over_UCL : UCL 초과율[%]. 각자 기준선 대비 -> 공정 비교지표(감지 민감도).
%   RMS/IMD_max : 차원(센서수) 의존 -> 참고용.
% =====================================================================================

clear; clc; close all;

xlsxFile = 'IMD_handuri_summary.xlsx';
if exist(xlsxFile,'file') ~= 2
    error(['%s 가 없습니다. 먼저 run_IMD_handuri_fixed.m 를 실행하세요. ', ...
           '(구 하드코딩 값은 오염 데이터라 사용하지 않습니다.)'], xlsxFile);
end
T = readtable(xlsxFile);

isEOT  = contains(string(T.Set),'EOT');
isFull = contains(string(T.Set),'Full');
condR   = [T.condR(isEOT),        T.condR(isFull)];
overUCL = [T.over_UCL_pct(isEOT), T.over_UCL_pct(isFull)];
RMS     = [T.RMS(isEOT),          T.RMS(isFull)];
IMDmax  = [T.IMD_max(isEOT),      T.IMD_max(isFull)];
fprintf('%s에서 데이터 로드 완료 (수정 트윈 기반)\n', xlsxFile);

labels = {'EOT (8 sensors)', 'Full (24 sensors)'};
cEOT  = [0.165 0.471 0.839];  cFull = [0.922 0.408 0.204];
barColors = [cEOT; cFull];  saveRes = '-r150';

% Figure 1: cond(R) - 로그 스케일
f1 = figure('Color','w','Position',[100 100 560 420]);
b1 = bar(condR,'FaceColor','flat'); b1.CData = barColors;
set(gca,'YScale','log','XTickLabel',labels,'FontSize',11);
ylabel('cond(R) (log scale)'); grid on;
title('공분산 조건수 cond(R) - 낮을수록 안정 [공정 비교지표]');
% y축 범위: EOT(작은 값) 아래까지 바닥을 내려 막대가 보이게 하고,
%           위쪽은 값 라벨/주석이 타이틀을 넘지 않도록 여유를 준다.
ylo = 10^floor(log10(min(condR))) / 3;   % 최소값(EOT) 아래 -> 막대 바닥
yhi = max(condR) * 12;                    % 상단 여유(라벨/주석 공간)
ylim([ylo, yhi]);
b1.BaseValue = ylo;                       % 로그축에서 막대를 바닥(ylo)부터 그림 -> EOT도 보임
for i=1:2
    text(i, condR(i)*2, sprintf('%.2e',condR(i)), ...
        'HorizontalAlignment','center','FontWeight','bold');
end
box on; set(gca,'Layer','bottom');   % 그리드를 막대 '뒤'로(막대 위에 겹쳐 보이지 않게)
print(f1,'compare_condR','-dpng',saveRes);

% Figure 2: over_UCL - 손상 감지율
f2 = figure('Color','w','Position',[120 120 560 420]);
b2 = bar(overUCL,'FaceColor','flat'); b2.CData = barColors;
set(gca,'XTickLabel',labels,'FontSize',11); ylabel('UCL exceedance ratio [%]'); grid on; set(gca,'Layer','bottom');
title('손상 감지율 (UCL 초과율) - 높을수록 민감 [공정 비교지표]');
for i=1:2, text(i,overUCL(i)+0.03*max(overUCL+eps),sprintf('%.2f%%',overUCL(i)),'HorizontalAlignment','center','FontWeight','bold'); end
ylim([0, max(overUCL+eps)*1.3]);
print(f2,'compare_overUCL','-dpng',saveRes);

% Figure 3: RMS (참고)
f3 = figure('Color','w','Position',[140 140 560 420]);
b3 = bar(RMS,'FaceColor','flat'); b3.CData = barColors;
set(gca,'XTickLabel',labels,'FontSize',11); ylabel('RMS of IMD'); grid on; set(gca,'Layer','bottom');
title('IMD RMS - 차원 의존 [참고용]');
for i=1:2, text(i,RMS(i)+0.02*max(RMS+eps),sprintf('%.3f',RMS(i)),'HorizontalAlignment','center','FontWeight','bold'); end
ylim([0, max(RMS+eps)*1.25]);
print(f3,'compare_RMS','-dpng',saveRes);

% Figure 4: IMD_max (참고)
f4 = figure('Color','w','Position',[160 160 560 420]);
b4 = bar(IMDmax,'FaceColor','flat'); b4.CData = barColors;
set(gca,'XTickLabel',labels,'FontSize',11); ylabel('IMD_{max}'); grid on; set(gca,'Layer','bottom');
title('최대 IMD - 차원 의존 [참고용]');
for i=1:2, text(i,IMDmax(i)+0.02*max(IMDmax+eps),sprintf('%.2f',IMDmax(i)),'HorizontalAlignment','center','FontWeight','bold'); end
ylim([0, max(IMDmax+eps)*1.2]);
print(f4,'compare_IMDmax','-dpng',saveRes);

fprintf('\n저장: compare_condR/overUCL/RMS/IMDmax.png\n');
fprintf('[해석] 공정지표(cond R, over_UCL)로 EOT 우수 여부 판단. RMS/IMD_max는 차원효과라 참고용.\n');
fprintf('[주의] Full(24)는 cond(R)이 커 R^-1 불안정 -> 판정은 EOT 기준.\n');

%% 모든 열린 figure를 .fig로 자동 저장 (PNG는 저장하지 않음)
save_all_figs_as_fig();

%% ---- 다음 실행 안내 (파이프라인 8/9 완료) ----
fprintf('\n================ 다음 실행 스크립트 ================\n');
fprintf('  [8/9] EOT vs Full 비교 완료 (그림 17)\n');
fprintf('  >> 다음 실행: plot_report_extra_figures.m\n');
fprintf('     (보조 그림 일괄: 그림 12·13·14·16 + IMD 손상 판정 성능 요약)\n');
fprintf('     ※ 이 한 스크립트가 위 그림들을 한 번에 plot하고 각각 .fig로 저장합니다.\n');
fprintf('====================================================\n');
