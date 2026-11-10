function plot_fig16_rms_rmd()
%PLOT_FIG16_RMS_IMD  [그림 16] IMD 손상 정도 지표 (RMS_IMD, DR_IMD) — EOT vs Full
%   무손상-손상 차 Delta_x = Xu - Xd 로 IMD 시계열을 산정하고,
%   무손상-무손상(계측잡음 n1-n2) 기준의 중심선 CL로부터
%     RMS_IMD = RMS(IMD - CL)  (강진구간),
%     DR_IMD  = (1 - RMS_IMD_undam / RMS_IMD_dam) * 100
%   을 EOT(8), Full(24)에 대해 산정하여 (좌) RMS_IMD, (우) DR_IMD 막대로 저장한다.
%   (정의: 8.1절 식 (27), Heo & Kim 2014. 계측잡음 seed는 imd_compute.m과 동일한 7 사용)
%
%   [필요 파일]  hangduri_24node_seismic_accel.xlsx  (sheet: Updated_FE)
%               hangduri_24node_cable4break_accel.xlsx (sheet: Cable4Break)

    undam_file  = 'hangduri_24node_seismic_accel.xlsx';    undam_sheet = 'Updated_FE';
    dam_file    = 'hangduri_24node_cable4break_accel.xlsx'; dam_sheet   = 'Cable4Break';
    eot   = [4 7 9 11 14 16 19 23];
    fs    = 100;   rms_start = 5;   rms_win = 40;   sigma_noise = 2.9e-4;
    nNode = 24;

    Xu = read_accel_sheet(undam_file, undam_sheet, nNode);
    Xd = read_accel_sheet(dam_file,   dam_sheet,   nNode);
    T  = min(size(Xu,1), size(Xd,1));  Xu = Xu(1:T,:);  Xd = Xd(1:T,:);

    sets  = {eot, 1:24};   names = {'EOT (8)','Full (24)'};
    ru = zeros(1,2); rd = zeros(1,2); dr = zeros(1,2);
    for s = 1:2
        [ru(s), rd(s), dr(s)] = rmd_metrics(Xu, Xd, sets{s}, fs, rms_start, rms_win, sigma_noise);
    end

    % Figure 1: RMS_{IMD} (별도 fig)
    figure('Color','w','Position',[100 100 560 400]);
    bar([ru(:), rd(:)]); grid on; box on; set(gca,'XTickLabel',names);
    ylabel('RMS_{IMD}'); title('RMS_{IMD}: undamaged vs damaged');
    legend({'Undamaged','Damaged'}, 'Location','northwest');
    savefig(gcf, 'fig16a_rms_imd.fig');
    fprintf('saved: fig16a_rms_imd.fig\n');

    % Figure 2: DR_{IMD} (별도 fig, 세트별 색 EOT/Full)
    figure('Color','w','Position',[130 130 560 400]);
    bDR = bar(dr, 'FaceColor','flat');
    bDR.CData(1,:) = [0.16 0.47 0.84];  bDR.CData(2,:) = [0.92 0.41 0.20];
    grid on; box on; set(gca,'XTickLabel',names);
    ylabel('DR_{IMD} [%]'); title('DR_{IMD} (damage ratio)'); ylim([0 100]);
    savefig(gcf, 'fig16b_dr_imd.fig');
    fprintf('saved: fig16b_dr_imd.fig  (EOT: %.2f->%.2f, DR %.1f%% | Full: %.2f->%.2f, DR %.1f%%)\n', ...
            ru(1),rd(1),dr(1), ru(2),rd(2),dr(2));
end

function [ruv, rdv, drv] = rmd_metrics(Xu, Xd, sens, fs, rms_start, rms_win, sigma)
    U = Xu(:,sens);  D = Xd(:,sens);  dX = U - D;
    m  = mean(dX,1);  R = cov(dX);  Ri = inv(R);
    dc = dX - m;      imd = sqrt(sum((dc*Ri).*dc, 2));           % 손상 IMD

    Tn = size(dX,1);  k = numel(sens);
    rs = RandStream('mt19937ar','Seed',7);                       % 재현성(로컬 스트림)
    dX0 = sigma*randn(rs,Tn,k) - sigma*randn(rs,Tn,k);           % 무손상-무손상 (n1-n2)
    m0 = mean(dX0,1); R0 = cov(dX0); Ri0 = inv(R0);
    imd0 = sqrt(sum(((dX0-m0)*Ri0).*(dX0-m0), 2));               % 무손상 IMD0
    CL = mean(imd0);                                             % 관리차트 중심선

    i0 = round(rms_start*fs) + 1;
    i1 = min(Tn, i0 + round(rms_win*fs) - 1);
    seg  = imd(i0:i1);   seg0 = imd0(i0:i1);
    ruv = sqrt(mean((seg0 - CL).^2));                            % RMS_IMD (무손상 기준 산포)
    rdv = sqrt(mean((seg  - CL).^2));                            % RMS_IMD (손상)
    drv = (1 - ruv/rdv) * 100;                                   % DR_IMD [%]
end

function X = read_accel_sheet(filename, sheet, nNode)
    if exist(filename,'file') ~= 2, error('파일 없음: %s', filename); end
    Traw = readtable(filename, 'Sheet', sheet);
    M = table2array(Traw);
    M = M(:, all(~isnan(M),1));
    X = M(:, end-nNode+1:end);
    X(~isfinite(X)) = 0;
end
