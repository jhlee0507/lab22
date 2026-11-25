function checkSurvey(root,cfg)
% Exercise the import offline. The records below exist only inside tempdir.
data = tempname();
mkdir(data);
clean = onCleanup(@() rmdir(data,'s')); %#ok<NASGU>
survey = fullfile(root,'data','gunja');
inputs = {'origin.csv','buildings.csv','building_holes.csv','label.txt','candidates.csv'};
for i = 1:numel(inputs), copyfile(fullfile(survey,inputs{i}),data); end
fetchSpectrumSites(data,@fixture);
map = loadGunjaMap(data,cfg);
assert(numel(map.buildings) == 1167 && numel(map.courtyards) == 1);
assert(numel(map.indoor) == 3721 && nnz(map.indoor) == 1441);
assert(nnz(strcmp(map.role,'service')) == 1 && nnz(strcmp(map.role,'external')) == 1);
assert(nnz(strcmp(map.role,'candidate')) == 8 && ~any(strcmp(map.siteId,'P05')));
xy = map.siteXY(strcmp(map.role,'service'),:);
assert(max(abs(xy-[36.79,21.23])) < 0.02); % Matches the independent PROJ conversion.
pointer = fullfile(data,'spectrum_snapshot.txt');
snapshot = strtrim(fileread(pointer));
sources = fileread(fullfile(data,snapshot,'site_sources.csv'));
assert(numel(regexp(sources,'\n')) == 4 && numel(strfind(sources,'"T1"')) == 1);
assert(isempty(strfind(sources,'DROP')));
try
    fetchSpectrumSites(data,@(~) struct('points',{{}}));
    error('test:expectedFailure','Invalid index was accepted.');
catch problem
    assert(strcmp(problem.identifier,'gunja:kcaIndex'));
end
assert(strcmp(strtrim(fileread(pointer)),snapshot));
assert(strcmp(sources,fileread(fullfile(data,snapshot,'site_sources.csv'))));

% Query the real courtyard at sub-grid scale. The normal 10 m grid misses it.
cfg.gridStepM = .01;
cfg.eastLimitsM = [-222.525,-222.515];
cfg.northLimitsM = [-153.48,-153.47];
inner = loadGunjaMap(data,cfg);
assert(~any(inner.indoor));
end

function answer = fixture(url)
% Two pages, one repeated link/permit and one colocated permit.
if ~isempty(strfind(url,'mobile_service.json'))
    assert(~isempty(strfind(url,'latitude=37.5572237&longitude=127.0795184')));
    answer = struct('points',{{'/fixture/a','/fixture/b','/fixture/a'}});
    return;
end
s = struct('uid','T1','customer_no',542604,'customer_name','에스케이텔레콤 주식회사', ...
    'service_name','이동전화(LTE)서비스 제공용(지상_기지국)','cls_name','기지국', ...
    'is_allow','Y','position',[127.0799348,37.5574150]);
if strcmp(url,'https://spectrummap.kr/fixture/a')
    answer = repmat(s,1,7);
    answer(2).uid = 'T2'; % Another permit at T1's position
    answer(3).customer_no = 542610; answer(3).uid = 'DROP-KT';
    answer(4).is_allow = 'N'; answer(4).uid = 'DROP-N';
    answer(5).service_name = 'LTE 옥내 기지국'; answer(5).uid = 'DROP-INDOOR';
    answer(6).service_name = '5G 지상 기지국'; answer(6).uid = 'DROP-NR';
    answer(7).position = [127.0795184,37.57]; answer(7).uid = 'DROP-FAR';
elseif strcmp(url,'https://spectrummap.kr/fixture/b')
    answer = [s,s];
    answer(2).uid = 'T3';
    answer(2).position = [127.0795184,37.5610]; % About 420 m north
else
    error('test:fixture','Unexpected URL.');
end
end
