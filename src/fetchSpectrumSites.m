function fetchSpectrumSites(dataDir, readJson)
% Build the baseline from the Spectrum Portal's public station records.
% A supplied reader lets the same import run against a saved test response.
if nargin < 2
    readJson = @readPortal;
end

base = 'https://spectrummap.kr';
originRow = readPlainCsv(fullfile(dataDir,'origin.csv'), ...
    'stop_id,station,longitude_deg,latitude_deg','%s%s%f%f');
origin = [originRow{3},originRow{4}];
if ~isequal(size(origin),[1,2]) || any(~isfinite(origin))
    error('gunja:origin','Expected one WGS84 origin.');
end
query = sprintf(['%s/gis/mobile_service.json?menuNo=300480&type=&latitude=%.7f' ...
    '&longitude=%.7f&zoom=16&visibleRadius=500'],base,origin(2),origin(1));
index = readJson(query);
if ~isstruct(index) || ~isfield(index,'points') || isempty(index.points)
    error('gunja:kcaIndex','No station detail links in the Spectrum Portal response.');
end
links = unique(cellstr(index.points));
records = cell(0,8);
for i = 1:numel(links)
    path = links{i};
    if ~strncmp(path,'/',1) || strncmp(path,'//',2)
        error('gunja:kcaLink','Unexpected station detail path.');
    end
    url = [base path];
    batch = readJson(url);
    if isempty(batch), continue; end
    fields = {'uid','customer_no','customer_name','service_name','cls_name','is_allow','position'};
    if ~isstruct(batch) || ~all(isfield(batch,fields))
        error('gunja:kcaFormat','Unrecognised station detail response at %s.',url);
    end
    for j = 1:numel(batch)
        s = batch(j);
        service = char(s.service_name);
        if ~strcmp(idText(s.customer_no),'542604') || ...
                ~strcmp(s.is_allow,'Y') || ~strcmp(s.cls_name,'기지국') || ...
                isempty(strfind(service,'LTE')) || isempty(strfind(service,'지상')) || ...
                isempty(strfind(service,'기지국')) || ~isempty(regexp(service,'옥내|지하|중계','once'))
            continue;
        end
        position = s.position;
        if iscell(position), position = str2double(position); end
        if ~isnumeric(position) || numel(position) ~= 2 || any(~isfinite(position(:))) || ...
                abs(position(1)) > 180 || abs(position(2)) > 90
            error('gunja:kcaPosition','Invalid WGS84 station coordinates in %s.',url);
        end
        position = reshape(position,1,2);
        [east,north] = localMetres(position,origin);
        if hypot(east,north) <= 500
            records(end+1,:) = {idText(s.uid),char(s.customer_name),service, ...
                position(1),position(2),east,north,url}; %#ok<AGROW>
        end
    end
end
if isempty(records)
    error('gunja:kcaEmpty','No SK Telecom above-ground LTE base station matched the survey.');
end
% Preserve every distinct permit, but model colocated permits as a single site.
[ids,first] = unique(records(:,1));
if any(cellfun(@isempty,ids))
    error('gunja:kcaId','Missing permit identifier.');
end
for i = 1:numel(ids)
    coordinates = cell2mat(records(strcmp(records(:,1),ids{i}),4:5));
    if size(unique(coordinates,'rows'),1) ~= 1
        error('gunja:kcaId','Conflicting positions for permit %s.',ids{i});
    end
end
records = records(first,:);
xy = round(cell2mat(records(:,6:7))*100)/100;
[locations,~,at] = unique(xy,'rows');
isService = all(abs(locations) <= 300,2);
if ~any(isService) || all(isService)
    error('gunja:kcaCoverage','The survey needs both service and external locations.');
end
siteId = cell(size(locations,1),1);
role = repmat({'external'},size(siteId));
role(isService) = {'service'};
siteId(isService) = arrayfun(@(i) sprintf('S%02d',i),(1:nnz(isService))','UniformOutput',false);
siteId(~isService) = arrayfun(@(i) sprintf('E%02d',i),(1:nnz(~isService))','UniformOutput',false);

candidates = readPlainCsv(fullfile(dataDir,'candidates.csv'), ...
    'site_id,building_id,east_m,north_m,longitude_deg,latitude_deg','%s%s%f%f%f%f');
candidateXY = [candidates{3},candidates{4}];
use = false(size(candidateXY,1),1);
for i = 1:numel(use)
    use(i) = all(hypot(locations(:,1)-candidateXY(i,1),locations(:,2)-candidateXY(i,2)) >= 30);
end
if nnz(use) < 2
    error('gunja:kcaCandidates','Fewer than two candidate sites clear the 30 m separation.');
end
% Publish one pointer to an immutable pair. A reader can keep its snapshot
% even if another survey refresh finishes while the simulation is running.
pointerTemp = tempname(dataDir);
[~,suffix] = fileparts(pointerTemp);
snapshot = ['kca-' datestr(now,'yyyymmdd') '-' suffix];
directory = fullfile(dataDir,snapshot);
[ok,msg] = mkdir(directory);
if ~ok, error('gunja:kcaWrite','%s',msg); end
try
    writeSources(directory,records,siteId(at),datestr(now,'yyyy-mm-dd'));
    writeSites(directory,[siteId;candidates{1}(use)],[role;repmat({'candidate'},nnz(use),1)], ...
        [locations;candidateXY(use,:)]);
    [fid,msg] = fopen(pointerTemp,'w');
    if fid < 0, error('gunja:kcaWrite','%s',msg); end
    fprintf(fid,'%s\n',snapshot);
    if fclose(fid) ~= 0, error('gunja:kcaWrite','Could not save snapshot name.'); end
    movefile(pointerTemp,fullfile(dataDir,'spectrum_snapshot.txt'),'f');
catch problem
    if isfile(pointerTemp), delete(pointerTemp); end
    rmdir(directory,'s');
    rethrow(problem);
end
end

function response = readPortal(url)
try
    raw = webread(url,weboptions('ContentType','text','Timeout',30));
catch problem
    error('gunja:kcaNetwork','Cannot read the Spectrum Portal at %s. %s',url,problem.message);
end
response = jsondecode(raw);
end

function values = readPlainCsv(path,header,format)
[fid,msg] = fopen(path,'r','n','UTF-8');
if fid < 0, error('gunja:kcaInput','%s: %s',path,msg); end
closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
if ~strcmp(strtrim(fgetl(fid)),header)
    error('gunja:kcaInput','Unexpected CSV header in %s.',path);
end
values = textscan(fid,format,'Delimiter',',');
end

function text = idText(value)
if isnumeric(value)
    if ~isscalar(value) || ~isfinite(value) || value ~= fix(value) || value > flintmax
        error('gunja:kcaId','Invalid numeric identifier.');
    end
    text = sprintf('%.0f',value);
else
    text = char(value);
end
end

function [east,north] = localMetres(position,origin)
% WGS84 geodetic to local topocentric ENU, both ellipsoidal heights zero.
lon = [origin(1);position(1)];
lat = [origin(2);position(2)];
f = 1/298.257223563;
e2 = f*(2-f);
N = 6378137 ./ sqrt(1-e2*sind(lat).^2);
dx = diff(N.*cosd(lat).*cosd(lon));
dy = diff(N.*cosd(lat).*sind(lon));
dz = diff(N*(1-e2).*sind(lat));
east = -sind(lon(1))*dx+cosd(lon(1))*dy;
north = -sind(lat(1))*(cosd(lon(1))*dx+sind(lon(1))*dy)+cosd(lat(1))*dz;
end

function writeSites(stage,ids,roles,xy)
[fid,msg] = fopen(fullfile(stage,'sites.csv'),'w','n','UTF-8');
if fid < 0, error('gunja:kcaWrite','%s',msg); end
closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'site_id,role,east_m,north_m,azimuth_deg\n');
for i = 1:numel(ids)
    fprintf(fid,'%s,%s,%.2f,%.2f,0\n',ids{i},roles{i},xy(i,1),xy(i,2));
end
end

function writeSources(stage,records,siteIds,dateRead)
[fid,msg] = fopen(fullfile(stage,'site_sources.csv'),'w','n','UTF-8');
if fid < 0, error('gunja:kcaWrite','%s',msg); end
closeFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'site_id,permit_uid,operator,service,longitude_deg,latitude_deg,source_url,retrieved_date\n');
for i = 1:size(records,1)
    fprintf(fid,'%s,%s,%s,%s,%.10f,%.10f,%s,%s\n',siteIds{i},quoted(records{i,1}), ...
        quoted(records{i,2}),quoted(records{i,3}),records{i,4},records{i,5},quoted(records{i,8}),dateRead);
end
end

function value = quoted(value)
value = ['"' strrep(value,'"','""') '"'];
end
