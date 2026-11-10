function plot_report_extra_figures()
%PLOT_REPORT_EXTRA_FIGURES  보고서 보조 그림들을 '한 번에' 생성 (파이프라인 9/9단계)
%   아래 그림들을 한 스크립트에서 순서대로 plot하고 각각 .fig로 저장한다.
%     (1) State-space accel response at EOT 8 sensors: baseline vs Cable4Break (full record)  [그림 12]
%     (2) Peak acceleration by node: undamaged vs damaged  +  difference (damaged-undamaged)  [그림 13]
%     (3) EOT 8-sensor averaged PSD: baseline vs damaged                                       [그림 14]
%     (4) RMS_{IMD} / DR_{IMD} : undamaged vs damaged (EOT vs Full)                            [그림 16]
%     (5) IMD 손상 판정 성능 요약 (표)                                                          [요약]
%
%   [필요 파일]  hangduri_24node_seismic_accel.xlsx     (sheet: Updated_FE)   = baseline(무손상)
%               hangduri_24node_cable4break_accel.xlsx  (sheet: Cable4Break)  = 손상
%               IMD_handuri_summary.xlsx  (성능 요약 표용, run_IMD_handuri_fixed.m 산출물)
%   [필요 툴박스] Signal Processing Toolbox (pwelch — 그림 14)

    undam_file = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';
    dam_file   = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet  = 'Cable4Break';
    eot   = [4 7 9 11 14 16 19 23];    % EOT 최적 8센서 (FE node 번호)
    nNode = 24;   fs = 100;

    % ---- 데이터 한 번만 읽기 (공용) ----
    Xu = read_accel_sheet(undam_file, undam_sheet, nNode);
    Xd = read_accel_sheet(dam_file,   dam_sheet,   nNode);
    T  = min(size(Xu,1), size(Xd,1));  Xu = Xu(1:T,:);  Xd = Xd(1:T,:);
    t  = (0:T-1)'/fs;

    % ---- 5개 그림 순서대로 ----
    fig_statespace_eot8(t, Xu, Xd, eot);        % (1) 그림 12
    fig_peak_by_node(Xu, Xd, nNode);            % (2) 그림 13
    fig_eot_avg_psd(Xu, Xd, eot, fs);           % (3) 그림 14
    fig_rms_rmd(Xu, Xd, eot, fs);               % (4) 그림 16
    fig_imd_summary();                          % (5) IMD 성능 요약 표

    fprintf('\n[보조 그림] 5개 figure 생성/저장 완료:\n');
    fprintf('  fig12_eot8_statespace.fig, fig13_peak_by_node.fig, fig14_eot_avg_psd.fig,\n');
    fprintf('  fig16_rms_rmd.fig, fig_imd_summary.fig\n');

    %% ---- 파이프라인 종료 안내 (9/9 완료) ----
    fprintf('\n================ 파이프라인 완료 ================\n');
    fprintf('  [9/9] 보고서 보조 그림 일괄 생성 완료 — 전체 파이프라인 끝.\n');
    fprintf('  (선택) plot_fig6_7_per_node.m : 단일상태 24절점 개별/격자 그림\n');
    fprintf('==================================================\n');
end

% =====================================================================================
% (1) 그림 12 : EOT 8센서 상태공간 가속도 응답 (전체 기록), baseline vs Cable4Break
% =====================================================================================
function fig_statespace_eot8(t, Xu, Xd, eot)
    cBase = [0.12 0.47 0.70];  cDam = [0.85 0.325 0.098];

    % 8센서(baseline+damaged) 전체 최대로 공통 y축(대칭) 계산
    amax = 0;
    for k = 1:numel(eot)
        amax = max([amax, max(abs(Xu(:,eot(k)))), max(abs(Xd(:,eot(k))))]);
    end
    yl = [-amax, amax] * 1.05;

    % (A) 8-in-one 격자 (y축 통일)
    figure('Color','w','Position',[60 60 1300 720]);
    for k = 1:numel(eot)
        nd = eot(k);
        subplot(4, 2, k); hold on;
        plot(t, Xu(:,nd), '-', 'Color', cBase, 'LineWidth', 0.6);
        plot(t, Xd(:,nd), '-', 'Color', cDam,  'LineWidth', 0.6);
        grid on; box on; set(gca,'Layer','top','FontSize',12);   % 눈금/축이름 글자 +2pt
        xlim([t(1) t(end)]);  ylim(yl);
        title(sprintf('KEOT sensor %d', nd), 'FontSize', 13, 'FontWeight','bold');
        if k > numel(eot)-2, xlabel('Time [s]', 'FontWeight','bold'); end
        if mod(k,2)==1,      ylabel('Accel [g]', 'FontWeight','bold'); end
        hL1 = plot(nan, nan, '-', 'Color', cBase, 'LineWidth', 2.5);   % 범례 전용 굵은 선 (데이터 없음)
        hL2 = plot(nan, nan, '-', 'Color', cDam,  'LineWidth', 2.5);
        legend([hL1 hL2], {'Undamage','Damage'}, 'Location','northeast', 'FontSize',9);
        hold off;
    end
    % (전체 제목 sgtitle 생략: 논문 그림 형식)
    savefig(gcf, 'fig12_eot8_statespace.fig');
    fprintf('saved: fig12_eot8_statespace.fig\n');

    % (B) 8개 센서 각각 개별 figure (동일 y축), 각각 .fig 저장
    for k = 1:numel(eot)
        nd = eot(k);
        figure('Color','w','Position',[80 80 760 380]); hold on;
        plot(t, Xu(:,nd), '-', 'Color', cBase, 'LineWidth', 0.7);
        plot(t, Xd(:,nd), '-', 'Color', cDam,  'LineWidth', 0.7);
        grid on; box on; set(gca,'Layer','top','FontSize',12);   % 눈금/축이름 글자 +2pt
        xlim([t(1) t(end)]);  ylim(yl);
        xlabel('Time [s]', 'FontWeight','bold');  ylabel('Accel [g]', 'FontWeight','bold');
        title(sprintf('KEOT sensor %d', nd), 'FontSize', 13, 'FontWeight','bold');
        hL1 = plot(nan, nan, '-', 'Color', cBase, 'LineWidth', 2.5);   % 범례 전용 굵은 선 (데이터 없음)
        hL2 = plot(nan, nan, '-', 'Color', cDam,  'LineWidth', 2.5);
        legend([hL1 hL2], {'Undamage','Damage'}, 'Location','northeast', 'FontSize',11);
        hold off;
        savefig(gcf, sprintf('fig12_eot8_node%02d.fig', nd));
    end
    fprintf('saved: fig12_eot8_node04/07/09/11/14/16/19/23.fig (개별 8개)\n');
end

% =====================================================================================
% (2) 그림 13 : 절점별 최대가속도 (무손상 vs 손상) + 차이(손상-무손상)
% =====================================================================================
function fig_peak_by_node(Xu, Xd, nNode)
    peakU = max(abs(Xu), [], 1);  peakD = max(abs(Xd), [], 1);  dpk = peakD - peakU;
    posC = [0.80 0.25 0.20];   % 양수(손상 증가) = 빨강
    negC = [0.20 0.45 0.70];   % 음수(손상 감소) = 파랑

    % Figure 1: 무손상 vs 손상 (별도 fig)
    figure('Color','w','Position',[100 100 950 400]);
    bar(1:nNode, [peakU(:), peakD(:)]); grid on; box on;
    xlabel('Node'); ylabel('Peak |accel| [g]');
    title('Peak acceleration by node: undamaged vs damaged');
    legend({'Undamaged','Damaged'}, 'Location','northwest'); set(gca,'XTick',1:nNode);
    savefig(gcf, 'fig13a_peak_by_node.fig');
    fprintf('saved: fig13a_peak_by_node.fig\n');

    % Figure 2: 차이(손상-무손상) — 부호별 색(양수 빨강/음수 파랑), 별도 fig
    figure('Color','w','Position',[120 120 950 400]);
    b = bar(1:nNode, dpk, 'FaceColor','flat');
    for i = 1:nNode
        if dpk(i) >= 0, b.CData(i,:) = posC; else, b.CData(i,:) = negC; end
    end
    grid on; box on;
    xlabel('Node'); ylabel('\Delta peak |accel| [g]');
    title('Peak acceleration difference (damaged - undamaged)'); set(gca,'XTick',1:nNode);
    savefig(gcf, 'fig13b_peak_diff.fig');
    fprintf('saved: fig13b_peak_diff.fig\n');
end

% =====================================================================================
% (3) 그림 14 : EOT 8센서 평균 PSD (baseline vs damaged)
% =====================================================================================
function fig_eot_avg_psd(Xu, Xd, eot, fs)
    nfft = 2048;  win = hann(nfft);  nov = nfft/2;
    PuAll = [];  PdAll = [];
    for j = eot
        [Pu, f] = pwelch(Xu(:,j), win, nov, nfft, fs);
        [Pd, ~] = pwelch(Xd(:,j), win, nov, nfft, fs);
        PuAll = [PuAll, Pu];  PdAll = [PdAll, Pd];  %#ok<AGROW>
    end
    Pu = mean(PuAll, 2);  Pd = mean(PdAll, 2);  mask = f <= 5;
    figure('Color','w','Position',[100 100 720 430]);
    semilogy(f(mask), Pu(mask), 'b-', 'LineWidth',1.5, 'DisplayName','Baseline (undamaged)'); hold on;
    semilogy(f(mask), Pd(mask), 'r-', 'LineWidth',1.5, 'DisplayName','Cable4Break (damaged)');
    grid on; xlabel('Frequency [Hz]'); ylabel('PSD [g^2/Hz]');
    title('EOT 8-sensor averaged PSD: baseline vs damaged');
    legend('Location','northeast'); xlim([0 5]); hold off;
    savefig(gcf, 'fig14_eot_avg_psd.fig');
    fprintf('saved: fig14_eot_avg_psd.fig\n');
end

% =====================================================================================
% (4) 그림 16 : RMS_{IMD} / DR_{IMD} (EOT vs Full)
% =====================================================================================
function fig_rms_rmd(Xu, Xd, eot, fs)
    rms_start = 5;  rms_win = 40;  sigma_noise = 2.9e-4;
    sets = {eot, 1:24};  names = {'EOT (8)','Full (24)'};
    ru = zeros(1,2); rd = zeros(1,2); dr = zeros(1,2);
    for s = 1:2
        [ru(s), rd(s), dr(s)] = rmd_metrics(Xu, Xd, sets{s}, fs, rms_start, rms_win, sigma_noise);
    end
    cEOT = [0.16 0.47 0.84];  cFull = [0.92 0.41 0.20];   % 세트별 색(EOT/Full)

    % Figure 1: RMS_{IMD} (별도 fig)
    figure('Color','w','Position',[100 100 560 400]);
    bar([ru(:), rd(:)]); grid on; box on; set(gca,'XTickLabel',names);
    ylabel('RMS_{IMD}'); title('RMS_{IMD}: undamaged vs damaged');
    legend({'Undamaged','Damaged'}, 'Location','northwest');
    savefig(gcf, 'fig16a_rms_imd.fig');
    fprintf('saved: fig16a_rms_imd.fig\n');

    % Figure 2: DR_{IMD} (별도 fig, 세트별 색 — 피크차이 그림과 구분)
    figure('Color','w','Position',[130 130 560 400]);
    bDR = bar(dr, 'FaceColor','flat');
    bDR.CData(1,:) = cEOT;  bDR.CData(2,:) = cFull;
    grid on; box on; set(gca,'XTickLabel',names);
    ylabel('DR_{IMD} [%]'); title('DR_{IMD} (damage ratio)'); ylim([0 100]);
    savefig(gcf, 'fig16b_dr_imd.fig');
    fprintf('saved: fig16b_dr_imd.fig  (EOT: %.2f->%.2f, DR %.1f%% | Full: %.2f->%.2f, DR %.1f%%)\n', ...
            ru(1),rd(1),dr(1), ru(2),rd(2),dr(2));
end

function [ruv, rdv, drv] = rmd_metrics(Xu, Xd, sens, fs, rms_start, rms_win, sigma)
    U = Xu(:,sens);  D = Xd(:,sens);  dX = U - D;
    m  = mean(dX,1);  R = cov(dX);  Ri = inv(R);
    dc = dX - m;      imd = sqrt(sum((dc*Ri).*dc, 2));
    Tn = size(dX,1);  k = numel(sens);
    rs = RandStream('mt19937ar','Seed',7);
    dX0 = sigma*randn(rs,Tn,k) - sigma*randn(rs,Tn,k);
    m0 = mean(dX0,1); R0 = cov(dX0); Ri0 = inv(R0);
    imd0 = sqrt(sum(((dX0-m0)*Ri0).*(dX0-m0), 2));
    CL = mean(imd0);
    i0 = round(rms_start*fs) + 1;  i1 = min(Tn, i0 + round(rms_win*fs) - 1);
    seg  = imd(i0:i1);   seg0 = imd0(i0:i1);
    ruv = sqrt(mean((seg0 - CL).^2));  rdv = sqrt(mean((seg - CL).^2));
    drv = (1 - ruv/rdv) * 100;
end

% =====================================================================================
% (5) IMD 손상 판정 성능 요약 (표 그림)
% =====================================================================================
function fig_imd_summary()
    xlsxFile = 'IMD_handuri_summary.xlsx';
    if exist(xlsxFile,'file') ~= 2
        warning('%s 가 없어 성능 요약 표를 건너뜁니다. 먼저 run_IMD_handuri_fixed.m 실행.', xlsxFile);
        return;
    end
    T = readtable(xlsxFile);
    isE = contains(string(T.Set),'EOT');  isF = contains(string(T.Set),'Full');
    rowName = {'UCL', 'RMS of IMD', 'over UCL [%]', 'cond(R)', 'IMD_{max}'};
    eotVal  = {num2str(T.UCL(isE),'%.3f'), num2str(T.RMS(isE),'%.3f'), ...
               num2str(T.over_UCL_pct(isE),'%.2f'), sprintf('%.2e',T.condR(isE)), num2str(T.IMD_max(isE),'%.2f')};
    fullVal = {num2str(T.UCL(isF),'%.3f'), num2str(T.RMS(isF),'%.3f'), ...
               num2str(T.over_UCL_pct(isF),'%.2f'), sprintf('%.2e',T.condR(isF)), num2str(T.IMD_max(isF),'%.2f')};
    nRow = numel(rowName);
    figure('Color','w','Position',[100 100 620 300]);
    axes('Position',[0.03 0.05 0.94 0.82]); axis off;
    xlim([0 3]); ylim([0 nRow+1]); hold on;
    headers = {'', 'EOT (8 sensors)', 'Full (24 sensors)'};  xc = [0.5 1.5 2.5];
    for c = 1:3
        text(xc(c), nRow+0.5, headers{c}, 'HorizontalAlignment','center','FontWeight','bold','FontSize',11);
    end
    for r = 1:nRow
        yy = nRow - r + 0.5;
        text(xc(1), yy, rowName{r}, 'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
        text(xc(2), yy, eotVal{r},  'HorizontalAlignment','center','FontSize',10);
        text(xc(3), yy, fullVal{r}, 'HorizontalAlignment','center','FontSize',10);
    end
    for r = 0:nRow, plot([0 3],[r r],'-','Color',[0.8 0.8 0.8]); end
    plot([0 3],[nRow+1 nRow+1],'k-','LineWidth',1.2);  plot([0 3],[nRow nRow],'k-','LineWidth',1.2);
    for c = 0:3, plot([c c],[0 nRow+1],'-','Color',[0.8 0.8 0.8]); end
    hold off;
    title('IMD 손상 판정 성능 요약 (EOT vs Full)', 'FontSize', 12);
    savefig(gcf, 'fig_imd_summary.fig');
    fprintf('saved: fig_imd_summary.fig\n');
end

% =====================================================================================
% 공용 유틸
% =====================================================================================
function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    Traw = readtable(filename, 'Sheet', sheet);
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));
    X = M(:, end-nNode+1:end);
    X(~isfinite(X)) = 0;
end
