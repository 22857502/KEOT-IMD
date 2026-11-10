function result = simulate_seismic_response_24node(M, C, K, t, ag, varargin)
%SIMULATE_SEISMIC_RESPONSE_24NODE El-Centro(또는 임의) 지반가속도에 대한
%   n노드(예: 한두리교 24노드) 상태공간모델의 가속도 응답 시뮬레이션
%
%   result = SIMULATE_SEISMIC_RESPONSE_24NODE(M, C, K, t, ag, Name,Value,...)
%
%   INPUT
%       M, C, K : n x n 질량/감쇠/강성 행렬
%       t       : nt x 1 시간벡터 [s] (균일 간격 권장)
%       ag      : nt x 1 지반가속도 [m/s^2]
%
%   Name-Value (선택)
%       'OutputType' : 'absolute'(기본) 또는 'relative'
%       'Label'      : 결과 구분용 문자열 (예: 'Initial FE', 'Updated FE')
%
%   OUTPUT (struct)
%       result.t        : 시간벡터
%       result.accel    : nt x n 가속도 응답 [m/s^2]
%       result.accel_g  : nt x n 가속도 응답 [g]
%       result.A,B,Cout,D,Gamma : 사용된 상태공간 행렬
%       result.outputType, result.label, result.n

    p = inputParser;
    addParameter(p, 'OutputType', 'absolute');
    addParameter(p, 'Label', '');
    parse(p, varargin{:});

    outputType = p.Results.OutputType;
    label = p.Results.Label;

    n = size(M,1);
    t = t(:);
    ag = ag(:);

    if length(t) ~= length(ag)
        error('simulate_seismic_response_24node:size', ...
            't와 ag의 길이가 일치해야 합니다 (%d vs %d).', length(t), length(ag));
    end

    [A, B, Cout, D, Gamma] = build_seismic_state_space(M, C, K, outputType);

    sys = ss(A, B, Cout, D);

    Y = lsim(sys, ag, t);   % nt x n, 가속도 응답 [m/s^2]

    result.t         = t;
    result.accel     = Y;
    result.accel_g   = Y / 9.80665;
    result.A         = A;
    result.B         = B;
    result.Cout      = Cout;
    result.D         = D;
    result.Gamma     = Gamma;
    result.outputType = outputType;
    result.label     = label;
    result.n         = n;

    fprintf('[%s] 지진응답 시뮬레이션 완료: %d step, %d node, peak|accel| = %.4f g (node %d)\n', ...
        ternary_local(isempty(label), 'unlabeled', label), ...
        length(t), n, max(max(abs(result.accel_g))), ...
        find(max(abs(result.accel_g),[],1) == max(max(abs(result.accel_g))), 1));
end

function out = ternary_local(cond, a, b)
    if cond
        out = a;
    else
        out = b;
    end
end
