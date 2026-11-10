function save_all_figs_as_fig(outDir, prefix)
%SAVE_ALL_FIGS_AS_FIG  현재 열려 있는 모든 figure를 각각 .fig(MATLAB figure) 파일로 저장.
%   PNG는 저장하지 않는다. 스크립트 맨 끝에서 한 번 호출하면
%   그 스크립트가 만든 모든 figure가 .fig로 자동 저장된다.
%
%   save_all_figs_as_fig()                : 현재 폴더에 저장
%   save_all_figs_as_fig(outDir)          : outDir 폴더에 저장(없으면 생성)
%   save_all_figs_as_fig(outDir, prefix)  : 파일명 앞에 prefix 부여
%
%   파일명 규칙: <prefix>fig<창번호>_<제목요약>.fig  (제목 없으면 창번호만)

    if nargin < 1 || isempty(outDir), outDir = pwd; end
    if nargin < 2, prefix = ''; end
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    figs = findall(0, 'Type', 'figure');
    if isempty(figs)
        fprintf('[save_all_figs_as_fig] 저장할 figure가 없습니다.\n');
        return;
    end
    % 창번호 오름차순(생성 순서에 가깝게)
    [~, ord] = sort(arrayfun(@(h) local_num(h), figs));
    figs = figs(ord);

    nSaved = 0;
    for k = 1:numel(figs)
        fh  = figs(k);
        num = local_num(fh);
        ttl = local_title(fh);
        if isempty(ttl)
            name = sprintf('%sfig%02d.fig', prefix, num);
        else
            name = sprintf('%sfig%02d_%s.fig', prefix, num, ttl);
        end
        try
            savefig(fh, fullfile(outDir, name));
            nSaved = nSaved + 1;
            fprintf('[save_all_figs_as_fig] saved: %s\n', name);
        catch ME
            fprintf('[save_all_figs_as_fig] 저장 실패(창 %d): %s\n', num, ME.message);
        end
    end
    fprintf('[save_all_figs_as_fig] 총 %d개 figure를 .fig로 저장했습니다 (%s).\n', nSaved, outDir);
end

function n = local_num(fh)
    if isprop(fh, 'Number') && ~isempty(fh.Number)
        n = double(fh.Number);
    else
        n = 0;   % Number 속성이 없는 경우
    end
end

function s = local_title(fh)
%LOCAL_TITLE  figure의 첫 번째 axes 제목(또는 sgtitle)을 파일명 안전 문자열로 반환
    s = '';
    ax = findall(fh, 'Type', 'axes');
    for a = 1:numel(ax)
        if ~isempty(ax(a).Title) && ~isempty(ax(a).Title.String)
            s = ax(a).Title.String; break;
        end
    end
    if iscell(s), s = s{1}; end
    s = char(s);
    s = regexprep(s, '[^\w가-힣]', '_');   % 파일명에 안전한 문자만
    s = regexprep(s, '_+', '_');
    s = regexprep(s, '^_|_$', '');
    if numel(s) > 40, s = s(1:40); end
end
