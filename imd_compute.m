function out = imd_compute(Xu, Xd, sensors, fs, rms_win_sec, rms_start_sec, Xu2)
% IMD_COMPUTE  Improved Mahalanobis Distance (Heo & Kim, 2014) — 한 손상 케이스 판정.
%
%   7번째 인자(Xu2) 유무로 두 모드가 자동 선택된다:
%
%   [모드1] Xu2 없음/[]  : 본 연구 사용
%       IMD 는 무손상-손상 차 Delta_x = Xu - Xd 에서 산정(기존 유지):
%         IMD_n = sqrt( (dx_n - m)^T R^{-1} (dx_n - m) )     (식 4)
%       관리한계(UCL)는 '무손상-무손상'에서 산정한다:
%         무손상을 두 번 계측한 셈으로 dX0 = (Xu+n1)-(Xu+n2) = n1-n2 (계측잡음차),
%         IMD0_n = sqrt((dX0_n - m0)^T R0^{-1} (dX0_n - m0)),
%         CL = mean(IMD0),  UCL = CL + 3*sigma0,  LCL = max(0, CL - 3*sigma0)  (식 5~7)
%       (마할라노비스 self-정규화라 UCL0는 잡음크기와 무관 -> 사실상 카이_k 한계.)
%       RMS 는 강진구간(rms_start ~ +rms_win) 손상 IMD 의 RMS.
%
%   [모드2] Xu2 = 행렬 (두번째 무손상)  : 무손상-무손상(Xu - Xu2)에서 관리한계 산정
%       무손상 baseline에서 m0,R0,CL0,UCL0를 고정하고, 손상 Delta_x=Xu-Xd를
%       그 고정 자로 재서 판정. 추가로 식(6)(7)의 RMS_RMD, DR_RMD 산출.
%
%   INPUT
%       Xu, Xd        : T x nNode 무손상/손상 가속도 [g]
%       sensors       : 센서(열) 인덱스 (예: EOT 8개, 또는 1:24)
%       fs            : 샘플링 주파수 [Hz]
%       rms_win_sec   : RMS 평가 창 길이 [s]
%       rms_start_sec : RMS 평가 창 시작 [s]
%       Xu2           : (선택) T x nNode 두번째 무손상 (모드2 전용)
%
%   OUTPUT (struct)
%       imd, CL, UCL, LCL, RMS, over_UCL, k, condR, mode, RMS_RMD, DR_RMD, imd0

    if nargin < 4 || isempty(fs),            fs = 100;           end
    if nargin < 5 || isempty(rms_win_sec),   rms_win_sec = 40;   end
    if nargin < 6 || isempty(rms_start_sec), rms_start_sec = 5;  end
    if nargin < 7,                           Xu2 = [];           end

    T = min(size(Xu,1), size(Xd,1));
    if ~isempty(Xu2), T = min(T, size(Xu2,1)); end
    U  = Xu(1:T, sensors);
    D  = Xd(1:T, sensors);
    dX = U - D;                                  % 무손상 - 손상 (판정 대상)

    i0 = round(rms_start_sec*fs) + 1;
    i1 = min(T, i0 + round(rms_win_sec*fs) - 1);

    if isempty(Xu2)
        % ================= 모드1: 자기참조 =================
        m  = mean(dX,1);  R = cov(dX);  Ri = inv(R);
        dc = dX - m;      imd = sqrt(sum((dc*Ri).*dc, 2));
        % ── UCL 산정만 무손상-무손상으로 교체 (그 외 IMD/RMS/over_UCL은 기존 유지) ──
        %   무손상 상태공간 응답을 '두 번 계측'한 셈: 같은 무손상에 독립 계측잡음을
        %   더한 두 실현의 차 dX0 = (Xu+n1)-(Xu+n2) = n1-n2 에서 관리한계를 산정.
        %   (결정론적 시뮬은 무손상 2개가 동일해 차=0 이므로 잡음이 필요.)
        %   주: 마할라노비스가 self-정규화라 UCL0는 sigma_noise와 무관, 사실상 카이_k 한계.
        Tn = size(dX,1);  kk = numel(sensors);
        sigma_noise = 2.9e-4;                         % 계측 잡음저 [g] (실측 무손상 PSD 고주파 평탄부)
        rs = RandStream('mt19937ar','Seed',7);        % 재현성(로컬 스트림, 전역 RNG 불변)
        dX0 = sigma_noise*randn(rs,Tn,kk) - sigma_noise*randn(rs,Tn,kk);   % 무손상 - 무손상
        m0 = mean(dX0,1); R0 = cov(dX0); Ri0 = inv(R0);
        imd0 = sqrt(sum(((dX0-m0)*Ri0).*(dX0-m0), 2));                     % 무손상 IMD0 (~카이_k)
        CL = mean(imd0);  SIG = std(imd0);
        UCL = CL + 3*SIG; LCL = max(0, CL - 3*SIG);   % UCL을 무손상-무손상에서 산정
        % ──────────────────────────────────────────────────────────────
        seg = imd(i0:i1); RMS = sqrt(mean(seg.^2));
        over_UCL = mean(imd > UCL);
        out = struct('imd',imd, 'CL',CL, 'UCL',UCL, 'LCL',LCL, 'RMS',RMS, ...
            'over_UCL',over_UCL, 'k',numel(sensors), 'condR',cond(R), ...
            'mode','self', 'RMS_RMD',NaN, 'DR_RMD',NaN, 'imd0',imd);
    else
        % ============ 모드2: 무손상-무손상(Xu-Xu2)에서 관리한계 ============
        U2  = Xu2(1:T, sensors);
        dX0 = U - U2;
        if all(abs(dX0(:)) < eps)
            error('두 무손상 응답이 동일해 차이가 0입니다. 서로 다른 무손상(Xu2)을 넣으세요.');
        end
        m0  = mean(dX0,1);  R0 = cov(dX0);  Ri0 = inv(R0);
        dc0 = dX0 - m0;     imd0 = sqrt(sum((dc0*Ri0).*dc0, 2));
        CL0 = mean(imd0);   SIG0 = std(imd0);
        UCL0 = CL0 + 3*SIG0;  LCL0 = CL0 - 3*SIG0;
        dc = dX - m0;       imd = sqrt(sum((dc*Ri0).*dc, 2));
        seg = imd(i0:i1);
        RMS     = sqrt(mean(seg.^2));
        RMS_RMD = sqrt(mean((seg - CL0).^2));           % 식(6)
        DR_RMD  = (1 - SIG0 / RMS_RMD) * 100;           % 식(7)
        over_UCL = mean(imd > UCL0);
        out = struct('imd',imd, 'CL',CL0, 'UCL',UCL0, 'LCL',LCL0, 'RMS',RMS, ...
            'over_UCL',over_UCL, 'k',numel(sensors), 'condR',cond(R0), ...
            'mode','fixed', 'RMS_RMD',RMS_RMD, 'DR_RMD',DR_RMD, 'imd0',imd0);
    end
end
