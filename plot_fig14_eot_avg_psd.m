function plot_fig14_eot_avg_psd()
%PLOT_FIG14_EOT_AVG_PSD  [그림 14] EOT 8센서 평균 가속도 PSD (무손상 vs 손상)
%   EOT 8센서(절점 4,7,9,11,14,16,19,23) 각각의 Welch PSD를 산정한 뒤
%   8채널에 대해 평균하여 무손상 vs 손상 스펙트럼을 겹쳐 그리고 저장한다.
%
%   [필요 파일]  hangduri_24node_seismic_accel.xlsx  (sheet: Updated_FE)
%               hangduri_24node_cable4break_accel.xlsx (sheet: Cable4Break)
%   [필요 툴박스] Signal Processing Toolbox (pwelch)

    undam_file  = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';
    dam_file    = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet   = 'Cable4Break';
    eot   = [4 7 9 11 14 16 19 23];    % EOT 최적 8센서
    fs    = 100;                       % 샘플링 주파수 [Hz]
    nfft  = 2048;                      % Welch 세그먼트 길이 (Δf ≈ fs/nfft ≈ 0.05 Hz)
    nNode = 24;

    Xu = read_accel_sheet(undam_file, undam_sheet, nNode);
    Xd = read_accel_sheet(dam_file,   dam_sheet,   nNode);
    T  = min(size(Xu,1), size(Xd,1));  Xu = Xu(1:T,:);  Xd = Xd(1:T,:);

    win = hann(nfft);  nov = nfft/2;
    PuAll = [];  PdAll = [];
    for j = eot
        [Pu, f] = pwelch(Xu(:,j), win, nov, nfft, fs);
        [Pd, ~] = pwelch(Xd(:,j), win, nov, nfft, fs);
        PuAll = [PuAll, Pu];  %#ok<AGROW>
        PdAll = [PdAll, Pd];  %#ok<AGROW>
    end
    Pu = mean(PuAll, 2);   Pd = mean(PdAll, 2);      % 8센서 평균 PSD
    mask = f <= 5;

    figure('Color','w','Position',[100 100 720 430]);
    semilogy(f(mask), Pu(mask), 'b-', 'LineWidth',1.5, 'DisplayName','Baseline (undamaged)'); hold on;
    semilogy(f(mask), Pd(mask), 'r-', 'LineWidth',1.5, 'DisplayName','Cable4Break (damaged)');
    grid on; xlabel('Frequency [Hz]'); ylabel('PSD [g^2/Hz]');
    title('EOT 8-sensor averaged PSD: baseline vs damaged');
    legend('Location','northeast'); xlim([0 5]); hold off;

    savefig(gcf, 'fig14_eot_avg_psd.fig');
    fprintf('saved: fig14_eot_avg_psd.fig\n');
end

function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    Traw = readtable(filename, 'Sheet', sheet);
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));
    X = M(:, end-nNode+1:end);
    X(~isfinite(X)) = 0;
end
