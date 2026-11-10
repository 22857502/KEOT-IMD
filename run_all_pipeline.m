function run_all_pipeline()
%RUN_ALL_PIPELINE  한두리교 IMD 전체 파이프라인(8단계)을 순서대로 한 번에 실행.
%   각 단계 스크립트를 순차 실행하며, 단계마다 그림은 .fig로 자동 저장된다.
%   중간 단계에서 오류가 나면 그 지점에서 멈추고 어떤 스크립트인지 알려준다.
%
%   [사용법]  모든 .m/데이터 파일이 있는 작업 폴더에서:  >> run_all_pipeline
%
%   [주의]
%     - 각 단계 스크립트는 시작 시 clear/close를 수행하므로, 이 구동기는
%       각 스크립트를 base 작업공간에서 독립 실행한다(evalin). 단계 간
%       주고받는 데이터는 모두 .mat/.xlsx 파일로 디스크를 경유한다.
%     - 특정 단계의 입력 파일(예: 계측 데이터, FE 질량/고유벡터 엑셀)이
%       폴더에 없으면 그 단계에서 멈춘다. 필요 없으면 아래 목록에서
%       해당 줄을 주석 처리(%)하고 다시 실행하면 된다.

    steps = {
        'hangduri_24node_update_and_state_space_merged_final', '모델 갱신 (그림 1·2 → merged_result.mat)'
        'hangduri_24node_damage_merged_fixed',                 '상태공간 변위 응답 검증 (그림 3·4)'
        'run_seismic_simulation_from_merged',                  '무손상 지진응답 (그림 5·6 → seismic_accel.xlsx)'
        'run_seismic_simulation_damage_fixed',                 '손상 지진응답 (그림 7 → cable4break_accel.xlsx)'
        'mode_selection_basis',                                '모드 선정 (그림 8·9·10 → mode_selection_result.mat)'
        'EOT_xlsx',                                            'EOT 센서 선정 (그림 11)'
        'run_IMD_handuri_fixed',                               'IMD 손상 판정 (그림 15 → summary.xlsx)'
        'plot_EOT_vs_Full_comparison_fixed',                   'EOT vs Full 비교 (그림 17)'
        'plot_report_extra_figures',                           '보조 그림 일괄 (그림 12·13·14·16 + IMD 성능요약)'
        };
    total = size(steps, 1);

    if exist('save_all_figs_as_fig', 'file') ~= 2
        warning('save_all_figs_as_fig.m 이 경로에 없습니다. .fig 자동 저장이 동작하지 않을 수 있습니다.');
    end

    t0 = tic;
    fprintf('\n########## 한두리교 IMD 전체 파이프라인 시작 (%d단계) ##########\n', total);
    for i = 1:total
        run_one_step(i, total, steps{i,1}, steps{i,2});
    end
    fprintf('\n########## 전체 파이프라인 완료 (총 소요 %.1f초) ##########\n', toc(t0));
    fprintf('9단계에 보조 그림(그림 12·13·14·16 + IMD 성능요약)이 plot_report_extra_figures로 포함됨.\n');
    fprintf('기타 선택: plot_fig6_7_per_node (단일상태 24절점 개별/격자)\n');
end

function run_one_step(idx, total, scriptName, desc)
    fprintf('\n############################################################\n');
    fprintf('### [%d/%d] %s\n', idx, total, desc);
    fprintf('###        실행: %s.m\n', scriptName);
    fprintf('############################################################\n');
    if exist(scriptName, 'file') ~= 2
        error('run_all_pipeline:missing', ...
            '[%d/%d] %s.m 을 찾을 수 없습니다. 작업 폴더/경로를 확인하세요.', idx, total, scriptName);
    end
    try
        evalin('base', scriptName);        % base 작업공간에서 독립 실행 (스크립트의 clear로부터 구동기 보호)
    catch ME
        fprintf(2, '\n>>> [중단] [%d/%d] %s.m 실행 중 오류가 발생했습니다:\n', idx, total, scriptName);
        fprintf(2, '      %s\n', ME.message);
        fprintf(2, '    이 단계의 입력 파일/설정을 확인해 해결한 뒤 다시 실행하세요.\n');
        fprintf(2, '    (그 단계가 불필요하면 run_all_pipeline.m 의 steps 목록에서 해당 줄을 주석 처리)\n');
        rethrow(ME);
    end
end
