function [t, ag] = generate_white_noise_input(dt, tEnd, varargin)
%GENERATE_WHITE_NOISE_INPUT 앰비언트(교통하중)와 통계적으로 유사한 광대역 랜덤
%   지반가속도 입력 생성
%
%   [t, ag] = GENERATE_WHITE_NOISE_INPUT(dt, tEnd, Name,Value,...)
%
%   El-Centro 같은 결정론적 지진파 대신, PSD 기반 모드선정(mode_selection_basis.m)과
%   일관되게 비교하기 위해 광대역 랜덤(백색잡음에 가까운) 입력을 생성합니다.
%   무손상(baseline)과 손상 시나리오를 "같은 통계적 특성의 입력"으로 시뮬레이션해야
%   PSD band power 차이를 순수하게 구조 변화(M,K)로 귀속시킬 수 있습니다.
%
%   INPUT
%       dt   : 시간간격 [s]
%       tEnd : 총 시뮬레이션 시간 [s]
%              한두리교 target mode 최소 간격(~0.08Hz) 기준 밴드폭을 겹치지 않게
%              잡으려면(약 0.03~0.04Hz) 충분한 주파수 해상도가 필요하므로,
%              tEnd는 최소 수백 초(예: 600s) 이상을 권장합니다.
%
%   Name-Value (선택)
%       'RmsAccel' : 목표 RMS 가속도 [m/s^2] (기본 0.05 m/s^2, 대략 5 gal 수준)
%       'Seed'     : 랜덤시드 (재현성 필요시 지정. 같은 seed면 같은 입력 재생성 가능)
%       'CutoffHz' : [f_low f_high] 대역통과 필터링 (기본 [] = 필터링 없음, 순수 백색)
%
%   OUTPUT
%       t  : nt x 1 시간벡터 [s]
%       ag : nt x 1 지반가속도 [m/s^2]
%
%   요구사항: 'CutoffHz'를 쓰는 경우 Signal Processing Toolbox (butter, filtfilt) 필요
%
%   주의: 실측 앰비언트(교통하중) 스펙트럼과 완전히 같지는 않습니다. 손상/무손상을
%         동일 입력 조건에서 비교하기 위한 "통제된 근사"로 이해하시면 됩니다.

    p = inputParser;
    addParameter(p, 'RmsAccel', 0.05);
    addParameter(p, 'Seed', []);
    addParameter(p, 'CutoffHz', []);
    parse(p, varargin{:});

    rmsAccel = p.Results.RmsAccel;
    seedVal  = p.Results.Seed;
    cutoffHz = p.Results.CutoffHz;

    if ~isempty(seedVal)
        rng(seedVal);
    end

    t  = (0:dt:tEnd).';
    nT = numel(t);
    fs = 1/dt;

    ag = randn(nT,1);

    if ~isempty(cutoffHz)
        if numel(cutoffHz) ~= 2 || cutoffHz(1) >= cutoffHz(2)
            error('generate_white_noise_input:cutoff', ...
                'CutoffHz는 [f_low f_high] (f_low < f_high) 형태여야 합니다.');
        end
        [b,a] = butter(4, cutoffHz/(fs/2), 'bandpass');
        ag = filtfilt(b, a, ag);
    end

    ag = ag / std(ag) * rmsAccel;

    fprintf('[generate_white_noise_input] %d step, dt=%.4fs, duration=%.1fs, RMS=%.4f m/s^2\n', ...
        nT, dt, tEnd, std(ag));
end
