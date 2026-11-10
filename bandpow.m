function bp = bandpow(f, P, f1, f2)
%BANDPOW 지정 주파수 대역 내 PSD 적분(band power) 계산
%
%   bp = BANDPOW(f, P, f1, f2)
%
%   INPUT
%       f, P   : psd_avg() 등에서 얻은 주파수벡터, PSD (같은 길이)
%       f1, f2 : 적분할 주파수 대역 [Hz] (f1 < f2)
%
%   OUTPUT
%       bp : 대역 내 PSD 적분값 (trapz 사다리꼴 적분)
%
%   주의: 인접한 두 모드의 대역이 겹치면(예: 중심주파수 간격이
%         2*bw보다 작으면) 같은 에너지가 두 모드에 중복 계산되어
%         excitation %의 합이 100%를 넘거나 두 모드의 상대적 강도
%         비교가 왜곡될 수 있습니다. 이 함수 자체는 겹침을 감지하지
%         않으므로, 호출하는 쪽(mode_selection_basis.m)에서
%         mode_freq 간 최소간격과 bw 값을 사전에 점검하는 것을
%         권장합니다.

    if f2 <= f1
        error('bandpow:range', 'f2는 f1보다 커야 합니다 (f1=%.3f, f2=%.3f).', f1, f2);
    end

    idx = f >= f1 & f <= f2;

    if nnz(idx) == 0
        warning('bandpow:noPoints', ...
            '[%.3f, %.3f] Hz 대역 내 PSD 포인트가 없습니다. bp=0으로 반환합니다.', f1, f2);
        bp = 0;
        return;
    end

    if nnz(idx) == 1
        warning('bandpow:onePoint', ...
            ['[%.3f, %.3f] Hz 대역 내 PSD 포인트가 1개뿐이라 근사 적분을 사용합니다. ' ...
             '주파수 해상도를 높이는 것을 고려하세요.'], f1, f2);
        bp = P(idx) * (f2 - f1);
        return;
    end

    bp = trapz(f(idx), P(idx));
end
