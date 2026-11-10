function [f, Pavg] = psd_avg(X, fs, varargin)
%PSD_AVG 다채널 가속도 신호의 채널평균 Welch PSD 계산
%
%   [f, Pavg] = PSD_AVG(X, fs, Name,Value,...)
%
%   INPUT
%       X  : nt x nCh 가속도 신호 (열 = 센서 채널, 예: S1..S8)
%       fs : 샘플링 주파수 [Hz]
%
%   Name-Value (선택)
%       'WindowSec'    : Welch window 길이 [s]
%                        (기본: min(16s, 데이터길이/8), 최소 64 샘플 보호)
%       'OverlapRatio' : window overlap 비율 (기본 0.5)
%       'Detrend'      : 'linear'(기본) | 'constant' | 'none'
%                        PSD 계산 전 채널별로 추세/DC 성분을 제거함.
%                        저주파 모드(예: 1Hz 이하)를 다룰 때, 센서 드리프트나
%                        DC 오프셋이 spectral leakage로 저주파 대역에 새어들어가
%                        해당 모드의 band power를 인위적으로 부풀릴 수 있으므로
%                        기본적으로 detrend를 적용함.
%
%   OUTPUT
%       f    : 주파수벡터 [Hz]
%       Pavg : 채널평균 PSD (f와 같은 길이)
%
%   요구사항: Signal Processing Toolbox (pwelch)
%
%   참고: window가 짧을수록 주파수 해상도가 나빠져 인접한 모드끼리
%         밴드파워가 섞일 수 있습니다. 모드 간격이 좁은 구간
%         (예: 6.922Hz와 7.463Hz처럼 0.5Hz 이내로 붙어있는 경우)이
%         있다면 WindowSec을 늘려 해상도를 높이는 것을 고려하세요.

    p = inputParser;
    addParameter(p, 'WindowSec', []);
    addParameter(p, 'OverlapRatio', 0.5);
    addParameter(p, 'Detrend', 'linear');   % 'linear' | 'constant' | 'none'
    parse(p, varargin{:});

    overlapRatio = p.Results.OverlapRatio;
    windowSec    = p.Results.WindowSec;
    detrendMode  = p.Results.Detrend;

    nt  = size(X,1);
    nCh = size(X,2);

    if isempty(windowSec)
        winLen = min(round(16*fs), floor(nt/8));
    else
        winLen = round(windowSec*fs);
    end
    winLen = max(winLen, 64);
    winLen = min(winLen, nt);

    noverlap = round(winLen*overlapRatio);
    nfft = 2^nextpow2(winLen);

    Pall = [];
    for ch = 1:nCh
        xCh = X(:,ch);
        if ~strcmpi(detrendMode, 'none')
            xCh = detrend(xCh, detrendMode);
        end
        [Pxx, f] = pwelch(xCh, hamming(winLen), noverlap, nfft, fs);
        if ch == 1
            Pall = zeros(numel(Pxx), nCh);
        end
        Pall(:,ch) = Pxx;
    end

    Pavg = mean(Pall, 2);

    fRes = f(2) - f(1);
    if fRes > 0.3
        warning('psd_avg:lowResolution', ...
            ['주파수 해상도가 %.3f Hz로 다소 낮습니다. 인접 모드(간격 < 약 %.2f Hz)는 ' ...
             '밴드파워 계산 시 서로 섞일 수 있으니 WindowSec을 늘리는 것을 고려하세요.'], ...
            fRes, 2*fRes);
    end
end
