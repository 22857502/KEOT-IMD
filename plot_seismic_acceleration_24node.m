function plot_seismic_acceleration_24node(result, varargin)
%PLOT_SEISMIC_ACCELERATION_24NODE 24노드 가속도 응답 결과 시각화
%
%   PLOT_SEISMIC_ACCELERATION_24NODE(result, Name,Value,...)
%
%   INPUT
%       result : simulate_seismic_response_24node()의 출력 struct.
%                여러 개를 cell로 넘기면 같은 그림에 겹쳐서 비교 플롯
%                (예: {result0, resultUp} -> Initial FE vs Updated FE)
%
%   Name-Value (선택)
%       'PlotStyle' : 'selected'   - 지정 노드만 한 figure에 subplot (기본값)
%                     'split_ns'   - N-line(1~12) / S-line(13~24)을
%                                    각각 별도 figure(그리드 subplot)로 분리
%                     'individual' - n개 노드 전체를 각각 별도 figure로 개별 plot
%                     'all'        - 위 3가지를 모두 그림
%       'Nodes'          : 'selected' 스타일에서 사용할 노드 목록
%                          (기본 [1 6 10 12 13 18 22 24])
%       'Unit'           : 'g'(기본) 또는 'm/s2'
%       'OutPrefix'      : 저장 파일 접두어. 지정하면 png로 저장, 미지정시 저장 안 함.
%       'NNodeLine'      : N-line/S-line 하나당 노드 수 (기본 12, pairFE 구조 기반.
%                          즉 node 1~NNodeLine = N-line, 다음 NNodeLine개 = S-line)
%       'ShowPeakProfile': 24(n)노드 전체 최대응답 프로파일 그림 표시 여부 (기본 true).
%                          split_ns/individual을 여러 번 호출할 때 중복 저장을
%                          피하려면 두 번째 호출부터 false로 주면 됨.
%       'CommonYLim'     : true면 모든 노드 subplot/개별 그림의 y축을 동일한
%                          대칭 범위 [-ymax, ymax]로 고정 (기본 false).
%                          ymax = 넘긴 모든 result·모든 노드의 |가속도| 최대값 * 1.05.
%                          절점 간 진폭을 같은 축에서 비교할 때 사용.
%       'ShowLegend'     : 각 그림에 범례 표시 여부 (기본 true). result가 하나뿐인
%                          단독 그림(Updated FE만 등)에서는 false 권장.
%       'PlotStyle'='grid': 전체 노드를 한 figure에 격자(6열)로 모아 그림.
%                          split_ns가 N/S로 나누는 것과 달리 24절점을 한 창에 표시.

    p = inputParser;
    addParameter(p, 'PlotStyle', 'selected');
    addParameter(p, 'Nodes', [1 6 10 12 13 18 22 24]);
    addParameter(p, 'Unit', 'g');
    addParameter(p, 'OutPrefix', '');
    addParameter(p, 'NNodeLine', 12);
    addParameter(p, 'ShowPeakProfile', true);
    addParameter(p, 'CommonYLim', false);
    addParameter(p, 'ShowLegend', true);
    addParameter(p, 'LineColors', []);   % [] 이면 기본 lines() 색. Nx3 RGB로 선색 직접 지정 가능.
    parse(p, varargin{:});

    plotStyle = lower(p.Results.PlotStyle);
    nodes     = p.Results.Nodes;
    unitStr   = p.Results.Unit;
    outPrefix = p.Results.OutPrefix;
    nNodeLine = p.Results.NNodeLine;
    showPeak  = p.Results.ShowPeakProfile;
    commonY   = p.Results.CommonYLim;
    showLegend = p.Results.ShowLegend;
    lineColors = p.Results.LineColors;

    if ~iscell(result)
        result = {result};
    end
    % 선 색: LineColors가 주어지면 그것을 사용(행이 모자라면 lines()로 보충), 아니면 기본 lines().
    if ~isempty(lineColors)
        colors = lineColors;
        if size(colors,1) < numel(result)
            colors = [colors; lines(numel(result))];   % 부족분 보충
        end
    else
        colors = lines(numel(result));
    end
    nTotalNode = result{1}.n;

    % --- 공통 y축 범위 계산 (CommonYLim=true 일 때만) ---
    ylimVec = [];
    if commonY
        ymax = 0;
        for r = 1:numel(result)
            R = result{r};
            if strcmpi(unitStr,'g'), a = R.accel_g; else, a = R.accel; end
            ymax = max(ymax, max(abs(a(:))));
        end
        if ymax > 0, ylimVec = [-ymax, ymax] * 1.05; end
    end

    doSelected   = any(strcmpi(plotStyle, {'selected','all'}));
    doSplitNS    = any(strcmpi(plotStyle, {'split_ns','all'}));
    doIndividual = any(strcmpi(plotStyle, {'individual','all'}));
    doGrid       = any(strcmpi(plotStyle, {'grid','all'}));

    if ~doSelected && ~doSplitNS && ~doIndividual && ~doGrid
        error('plot_seismic_acceleration_24node:PlotStyle', ...
            'PlotStyle은 ''selected'', ''split_ns'', ''individual'', ''grid'', ''all'' 중 하나여야 합니다.');
    end

    %% ---- STYLE 4: 전체 노드를 한 figure에 격자(6열)로 (24-in-one) ----
    if doGrid
        figure('Name','Seismic acceleration response - all nodes (grid)');
        nCol = 6;
        nRow = ceil(nTotalNode/nCol);
        for k = 1:nTotalNode
            subplot(nRow, nCol, k);
            plot_node_curves_local(k, result, unitStr, colors);
            title(sprintf('Node %d', k), 'FontSize', 8);
            set(gca, 'FontSize', 7);
            if ~isempty(ylimVec), ylim(ylimVec); end
            if showLegend && k == 1
                legend('show','Location','northeast');
            end
        end
        sgtitle(sprintf('El-Centro seismic acceleration response - all %d nodes', nTotalNode));
        if ~isempty(outPrefix)
            saveas(gcf, [outPrefix '_seismic_grid24.png']);
        end
    end

    %% ---- STYLE 1: 지정 노드만 한 figure에 subplot (기존 방식) ----
    if doSelected
        figure('Name','Seismic acceleration response - selected nodes');
        nNodePlot = numel(nodes);
        nCol = 2;
        nRow = ceil(nNodePlot/nCol);

        for k = 1:nNodePlot
            subplot(nRow, nCol, k);
            plot_node_curves_local(nodes(k), result, unitStr, colors);
            title(sprintf('Node %d', nodes(k)));
            if ~isempty(ylimVec), ylim(ylimVec); end
            if showLegend && k == 1
                legend('show','Location','northeast');
            end
        end
        sgtitle('El-Centro seismic acceleration response (selected nodes)');

        if ~isempty(outPrefix)
            saveas(gcf, [outPrefix '_seismic_selected_nodes.png']);
        end
    end

    %% ---- STYLE 2: N-line / S-line 각각 별도 figure로 분리 ----
    if doSplitNS
        if mod(nTotalNode, nNodeLine) ~= 0
            warning('plot_seismic_acceleration_24node:splitNS', ...
                '전체 노드 수(%d)가 NNodeLine(%d)으로 나누어 떨어지지 않습니다. N/S 분할이 예상과 다를 수 있습니다.', ...
                nTotalNode, nNodeLine);
        end

        nCol = 3;
        nRow = ceil(nNodeLine/nCol);

        % --- N-line (node 1 ~ nNodeLine) ---
        nLineIdx = 1:min(nNodeLine, nTotalNode);
        figure('Name','Seismic acceleration response - N-line');
        for k = 1:numel(nLineIdx)
            subplot(nRow, nCol, k);
            plot_node_curves_local(nLineIdx(k), result, unitStr, colors);
            title(sprintf('Node %d (N%d)', nLineIdx(k), k));
            if ~isempty(ylimVec), ylim(ylimVec); end
            if showLegend && k == 1
                legend('show','Location','northeast');
            end
        end
        sgtitle(sprintf('El-Centro seismic acceleration response - N-line (node 1-%d)', numel(nLineIdx)));

        if ~isempty(outPrefix)
            saveas(gcf, [outPrefix '_seismic_Nline.png']);
        end

        % --- S-line (node nNodeLine+1 ~ 2*nNodeLine) ---
        sLineIdx = (nNodeLine+1):min(2*nNodeLine, nTotalNode);
        if ~isempty(sLineIdx)
            figure('Name','Seismic acceleration response - S-line');
            for k = 1:numel(sLineIdx)
                subplot(nRow, nCol, k);
                plot_node_curves_local(sLineIdx(k), result, unitStr, colors);
                title(sprintf('Node %d (S%d)', sLineIdx(k), k));
                if ~isempty(ylimVec), ylim(ylimVec); end
                if showLegend && k == 1
                    legend('show','Location','northeast');
                end
            end
            sgtitle(sprintf('El-Centro seismic acceleration response - S-line (node %d-%d)', ...
                sLineIdx(1), sLineIdx(end)));

            if ~isempty(outPrefix)
                saveas(gcf, [outPrefix '_seismic_Sline.png']);
            end
        else
            warning('plot_seismic_acceleration_24node:noSLine', ...
                'S-line에 해당하는 노드가 없습니다 (nTotalNode=%d, NNodeLine=%d).', nTotalNode, nNodeLine);
        end
    end

    %% ---- STYLE 3: n개 노드 각각 별도 figure로 개별 plot ----
    if doIndividual
        for nodeIdx = 1:nTotalNode
            figure('Name', sprintf('Seismic acceleration response - node %d', nodeIdx));
            plot_node_curves_local(nodeIdx, result, unitStr, colors);
            title(sprintf('Node %d acceleration response (El-Centro)', nodeIdx));
            if ~isempty(ylimVec), ylim(ylimVec); end
            if showLegend, legend('show','Location','northeast'); end

            if ~isempty(outPrefix)
                saveas(gcf, sprintf('%s_seismic_node%02d.png', outPrefix, nodeIdx));
            end
        end
    end

    %% ---- n노드 전체 최대응답 프로파일 (선택적으로 표시) ----
    if showPeak
        figure('Name','Peak acceleration profile - all nodes');
        hold on;
        yl = 'Peak accel [g]';
        for r = 1:numel(result)
            R = result{r};
            if strcmpi(unitStr,'g')
                peakVal = max(abs(R.accel_g), [], 1);
                yl = 'Peak accel [g]';
            else
                peakVal = max(abs(R.accel), [], 1);
                yl = 'Peak accel [m/s^2]';
            end

            if isempty(R.label)
                dispName = sprintf('Result %d', r);
            else
                dispName = R.label;
            end

            plot(1:R.n, peakVal, 'o-', 'Color', colors(r,:), 'LineWidth', 1.5, ...
                'DisplayName', dispName);
        end
        grid on;
        xlabel('FE node');
        ylabel(yl);
        title('Peak acceleration by node (El-Centro input)');
        if showLegend, legend('show','Location','northeast'); end
        hold off;

        if ~isempty(outPrefix)
            saveas(gcf, [outPrefix '_seismic_peak_profile.png']);
        end
    end
end

function plot_node_curves_local(nodeIdx, result, unitStr, colors)
%PLOT_NODE_CURVES_LOCAL 현재 axes에 지정 노드의 가속도 시간이력을 (여러 result) 겹쳐 그림
    hold on;
    yl = 'Accel [g]';
    for r = 1:numel(result)
        R = result{r};
        if strcmpi(unitStr,'g')
            y = R.accel_g(:,nodeIdx);
            yl = 'Accel [g]';
        else
            y = R.accel(:,nodeIdx);
            yl = 'Accel [m/s^2]';
        end

        if isempty(R.label)
            dispName = sprintf('Result %d', r);
        else
            dispName = R.label;
        end

        plot(R.t, y, 'Color', colors(r,:), 'LineWidth', 1.0, 'DisplayName', dispName);
    end
    grid on;
    xlabel('Time [s]');
    ylabel(yl);
    hold off;
end
