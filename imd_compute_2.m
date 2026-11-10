function out = imd_compute(Xu, Xd, sensors, fs, rms_win_sec, rms_start_sec, base)
% IMD_COMPUTE  Improved Mahalanobis Distance (Heo & Kim, 2014) — 한 손상 케이스 판정.
%
%   7번째 인자(base)로 세 가지 모드가 자동 선택된다:
%
%   [모드1] base 없음/[]  : 자기참조 (하위호환)
%       dX = Xu - Xd 에서 m,R,UCL 을 그대로 산정 (손상 자체에서 UCL이 나와
%       손상 정도와 무관해지는 한계가 있음 -> 권장하지 않음).
%
%   [모드2] base = 행렬 Xu2 : 무손상-무손상(Xu - Xu2)에서 UCL 산정 (하위호환)
%       서로 다른 두 무손상 응답이 있을 때 사용.
%
%   [모드3] base = 구조체 (build_noise_baseline 출력) : 계측잡음 기반 고정 baseline (권장)
%       무손상 baseline에서 고정한 m0,R0,CL0,UCL0(식 5~7)을 사용하고,
%       손상 응답에 동일 잡음모델을 부가해 IMD를 계산·판정한다.
%       추가로 식(6)(7)의 RMS_RMD, DR_RMD 를 산출한다.
%
%   INPUT
%       Xu, Xd        : T x nNode 무손상(기준상태)/손상 가속도 [g]
%       sensors       : 센서(열) 인덱스 (모드3에서는 base.sensors가 우선)
%       fs            : 샘플링 주파수 [Hz]
%       rms_win_sec   : RMS 평가 창 길이 [s]
%       rms_start_sec : RMS 평가 창 시작 [s]
%       base          : [] | 행렬 Xu2 | 구조체(build_noise_baseline)
%
%   OUTPUT (struct)
%       imd, CL, UCL, LCL, RMS, over_UCL, k, condR, mode, RMS_RMD, DR_RMD, imd0
%
%   의존(모드3): bandlimited_noise.m

    if nargin < 4 || isempty(fs),            fs = 100;           end
    if nargin < 5 || isempty(rms_win_sec),   rms_win_sec = 40;   end
    if nargin < 6 || isempty(rms_start_sec), rms_start_sec = 5;  end
    if nargin < 7,                           base = [];          end

    % ===================== 모드3: 계측잡음 기반 고정 baseline =====================
    if isstruct(base)
        s = base.sensors(:).';
        T = min([size(Xu,1), size(Xd,1), size(base.nref,1)]);

        U  = Xu(1:T, s) + base.nref(1:T, :);                     % 노이지 기준 무손상(동일 실현)
        nd = bandlimited_noise(T, numel(s), base.fs, base.sigma, base.fcut);
        D  = Xd(1:T, s) + nd;                                    % 노이지 손상

        dX  = U - D;                                             % 손상 판정 차분
        dc  = dX - base.m0;
        imd = sqrt(sum((dc*base.Ri0).*dc, 2));                   % 고정 m0,R0로 IMD

        CL = base.CL0;  UCL = base.UCL0;  LCL = base.LCL0;
        i0 = round(rms_start_sec*fs) + 1;
        i1 = min(T, i0 + round(rms_win_sec*fs) - 1);
        seg = imd(i0:i1);
        RMS     = sqrt(mean(seg.^2));                            % 참고 RMS(IMD)
        RMS_RMD = sqrt(mean((seg - CL).^2));                     % 식(6)
        DR_RMD  = (1 - base.rms_rmd_undam / RMS_RMD) * 100;      % 식(7)
        over_UCL = mean(imd > UCL);

        out = struct('imd',imd, 'CL',CL, 'UCL',UCL, 'LCL',LCL, 'RMS',RMS, ...
            'over_UCL',over_UCL, 'k',numel(s), 'condR',cond(base.R0), ...
            'mode','fixed_noise', 'RMS_RMD',RMS_RMD, 'DR_RMD',DR_RMD, 'imd0',base.imd0);
        return;
    end

    % ===================== 모드1/2 (하위호환) =====================
    T = min(size(Xu,1), size(Xd,1));
    if ~isempty(base), T = min(T, size(base,1)); end            % 여기서 base는 행렬 Xu2
    U  = Xu(1:T, sensors);
    D  = Xd(1:T, sensors);
    dX = U - D;

    i0 = round(rms_start_sec*fs) + 1;
    i1 = min(T, i0 + round(rms_win_sec*fs) - 1);

    if isempty(base)
        % ----- 모드1: 자기참조 -----
        m = mean(dX,1);  R = cov(dX);  Ri = inv(R);
        dc = dX - m;     imd = sqrt(sum((dc*Ri).*dc, 2));
        CL = mean(imd);  SIG = std(imd);
        UCL = CL + 3*SIG;  LCL = CL - 3*SIG;
        seg = imd(i0:i1);  RMS = sqrt(mean(seg.^2));
        over_UCL = mean(imd > UCL);
        out = struct('imd',imd, 'CL',CL, 'UCL',UCL, 'LCL',LCL, 'RMS',RMS, ...
            'over_UCL',over_UCL, 'k',numel(sensors), 'condR',cond(R), ...
            'mode','self', 'RMS_RMD',NaN, 'DR_RMD',NaN, 'imd0',imd);
    else
        % ----- 모드2: 무손상-무손상(Xu-Xu2) -----
        Xu2 = base;  U2 = Xu2(1:T, sensors);  dX0 = U - U2;
        if all(abs(dX0(:)) < eps)
            error('두 무손상 응답이 동일해 차이가 0입니다. 서로 다른 무손상(Xu2)을 넣으세요.');
        end
        m0 = mean(dX0,1);  R0 = cov(dX0);  Ri0 = inv(R0);
        dc0 = dX0 - m0;    imd0 = sqrt(sum((dc0*Ri0).*dc0, 2));
        CL0 = mean(imd0);  SIG0 = std(imd0);
        UCL0 = CL0 + 3*SIG0;  LCL0 = CL0 - 3*SIG0;
        dc = dX - m0;      imd = sqrt(sum((dc*Ri0).*dc, 2));
        seg = imd(i0:i1);
        RMS     = sqrt(mean(seg.^2));
        RMS_RMD = sqrt(mean((seg - CL0).^2));
        DR_RMD  = (1 - SIG0 / RMS_RMD) * 100;
        over_UCL = mean(imd > UCL0);
        out = struct('imd',imd, 'CL',CL0, 'UCL',UCL0, 'LCL',LCL0, 'RMS',RMS, ...
            'over_UCL',over_UCL, 'k',numel(sensors), 'condR',cond(R0), ...
            'mode','fixed', 'RMS_RMD',RMS_RMD, 'DR_RMD',DR_RMD, 'imd0',imd0);
    end
end
