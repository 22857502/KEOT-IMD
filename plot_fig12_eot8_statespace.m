function plot_fig12_eot8_statespace()
%PLOT_FIG12_EOT8_STATESPACE  [그림 12] EOT 8센서 상태공간 가속도 응답 (전체 기록)
%   baseline(무손상=Updated_FE) vs Cable4Break(손상)을 EOT 최적 8센서에서 겹쳐 그린다.
%   전체 64초 기록을 그대로 표시하고 .fig로 저장한다.
%
%   [필요 파일]  hangduri_24node_seismic_accel.xlsx     (sheet: Updated_FE)  = baseline
%               hangduri_24node_cable4break_accel.xlsx  (sheet: Cable4Break) = 손상

    undam_file = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';
    dam_file   = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet  = 'Cable4Break';
    eot = [4 7 9 11 14 16 19 23];    % EOT 최적 8센서 (FE node 번호)
    nNode = 24;  fs = 100;

    Xu = read_accel_sheet(undam_file, undam_sheet, nNode);
    Xd = read_accel_sheet(dam_file,   dam_sheet,   nNode);
    T  = min(size(Xu,1), size(Xd,1));  Xu = Xu(1:T,:);  Xd = Xd(1:T,:);
    t  = (0:T-1)'/fs;                 % 전체 기록 (약 64초)

    cBase = [0.12 0.47 0.70];        % baseline(파랑)
    cDam  = [0.85 0.325 0.098];      % Cable4Break(주황)

    % 8센서(무손상+손상) 전체 최대로 공통 y축(대칭) 계산
    amax = max([max(max(abs(Xu(:,eot)))), max(max(abs(Xd(:,eot))))]);
    yl = [-amax, amax] * 1.05;

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
    fprintf('saved: fig12_eot8_statespace.fig  (EOT 8센서 %s, 전체 %.1f초)\n', mat2str(eot), t(end));
end

function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    Traw = readtable(filename, 'Sheet', sheet);
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));
    X = M(:, end-nNode+1:end);
    X(~isfinite(X)) = 0;
end
