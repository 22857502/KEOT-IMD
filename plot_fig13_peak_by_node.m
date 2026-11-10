function plot_fig13_peak_by_node()
%PLOT_FIG13_PEAK_BY_NODE  [그림 13] 절점별 최대가속도 (좌: 무손상 vs 손상, 우: 차이)
%   무손상/손상 가속도 엑셀에서 24절점 최대 |가속도|를 산정하고
%     (1) 무손상 vs 손상 막대 비교
%     (2) 손상-무손상 차이 막대
%   를 한 figure(2패널)에 그린 뒤 fig13_peak_by_node.png 로 저장한다.
%
%   [필요 파일]  hangduri_24node_seismic_accel.xlsx  (sheet: Updated_FE)
%               hangduri_24node_cable4break_accel.xlsx (sheet: Cable4Break)

    undam_file  = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';
    dam_file    = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet   = 'Cable4Break';
    nNode = 24;

    Xu = read_accel_sheet(undam_file, undam_sheet, nNode);   % T x 24 [g]
    Xd = read_accel_sheet(dam_file,   dam_sheet,   nNode);
    T  = min(size(Xu,1), size(Xd,1));  Xu = Xu(1:T,:);  Xd = Xd(1:T,:);

    peakU = max(abs(Xu), [], 1);      % 1 x 24
    peakD = max(abs(Xd), [], 1);
    dpk   = peakD - peakU;

    figure('Color','w','Position',[100 100 1000 380]);

    subplot(1,2,1);
    bar(1:nNode, [peakU(:), peakD(:)]); grid on;
    xlabel('Node'); ylabel('Peak |accel| [g]');
    title('Peak acceleration by node: undamaged vs damaged');
    legend({'Undamaged','Damaged'}, 'Location','northwest');
    set(gca,'XTick',1:nNode);

    subplot(1,2,2);
    bar(1:nNode, dpk); grid on;
    xlabel('Node'); ylabel('\Delta peak |accel| [g]');
    title('Peak acceleration difference (damaged - undamaged)');
    set(gca,'XTick',1:nNode);

    savefig(gcf, 'fig13_peak_by_node.fig');
    fprintf('saved: fig13_peak_by_node.fig\n');
end

function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    Traw = readtable(filename, 'Sheet', sheet);
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));              % 전부 NaN인 열 제거
    X = M(:, end-nNode+1:end);               % 마지막 24열 = 절점 (시간열 제외)
    X(~isfinite(X)) = 0;
end
