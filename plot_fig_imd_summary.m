function plot_fig_imd_summary()
%PLOT_FIG_IMD_SUMMARY  [IMD 손상 판정 성능 요약] EOT(8) vs Full(24) 표 그림
%   run_IMD_handuri_fixed.m가 만든 IMD_handuri_summary.xlsx에서 지표를 읽어
%   UCL, RMS, over_UCL[%], cond(R), IMD_max 를 한 장의 표(그림)로 그리고 .fig 저장.
%
%   [필요 파일]  IMD_handuri_summary.xlsx  (컬럼: Set, condR, over_UCL_pct, RMS, IMD_max, UCL)

    xlsxFile = 'IMD_handuri_summary.xlsx';
    if exist(xlsxFile,'file') ~= 2
        error('%s 가 없습니다. 먼저 run_IMD_handuri_fixed.m 를 실행하세요.', xlsxFile);
    end
    T = readtable(xlsxFile);
    isE = contains(string(T.Set),'EOT');  isF = contains(string(T.Set),'Full');

    % 표에 넣을 지표 (행: 지표, 열: EOT / Full)
    rowName = {'UCL', 'RMS of IMD', 'over UCL [%]', 'cond(R)', 'IMD_{max}'};
    eotVal  = {num2str(T.UCL(isE),'%.3f'),  num2str(T.RMS(isE),'%.3f'), ...
               num2str(T.over_UCL_pct(isE),'%.2f'), sprintf('%.2e',T.condR(isE)), ...
               num2str(T.IMD_max(isE),'%.2f')};
    fullVal = {num2str(T.UCL(isF),'%.3f'),  num2str(T.RMS(isF),'%.3f'), ...
               num2str(T.over_UCL_pct(isF),'%.2f'), sprintf('%.2e',T.condR(isF)), ...
               num2str(T.IMD_max(isF),'%.2f')};

    nRow = numel(rowName);
    figure('Color','w','Position',[100 100 620 300]);
    ax = axes('Position',[0.03 0.05 0.94 0.82]); axis(ax,'off');
    xlim(ax,[0 3]); ylim(ax,[0 nRow+1]);

    % 헤더
    headers = {'', 'EOT (8 sensors)', 'Full (24 sensors)'};
    xc = [0.5 1.5 2.5];
    for c = 1:3
        text(xc(c), nRow+0.5, headers{c}, 'HorizontalAlignment','center', ...
            'FontWeight','bold','FontSize',11);
    end
    % 데이터 행
    for r = 1:nRow
        yy = nRow - r + 0.5;
        text(xc(1), yy, rowName{r},  'HorizontalAlignment','center','FontSize',10,'FontWeight','bold');
        text(xc(2), yy, eotVal{r},   'HorizontalAlignment','center','FontSize',10);
        text(xc(3), yy, fullVal{r},  'HorizontalAlignment','center','FontSize',10);
    end
    % 격자선
    hold on;
    for r = 0:nRow, plot([0 3],[r r],'-','Color',[0.8 0.8 0.8]); end
    plot([0 3],[nRow+1 nRow+1],'k-','LineWidth',1.2);   % 상단
    plot([0 3],[nRow nRow],'k-','LineWidth',1.2);       % 헤더 밑줄
    for c = 0:3, plot([c c],[0 nRow+1],'-','Color',[0.8 0.8 0.8]); end
    hold off;

    title('IMD 손상 판정 성능 요약 (EOT vs Full)', 'FontSize', 12);

    savefig(gcf, 'fig_imd_summary.fig');
    fprintf('saved: fig_imd_summary.fig  (IMD 성능 요약: EOT/Full UCL·RMS·over_UCL·cond(R)·IMD_max)\n');
end
