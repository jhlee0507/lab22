function map = loadGunjaMap(dataDir, cfg)
% Load site roles and building rings in local metres, east/north of the origin.
map.label = strtrim(fileread(fullfile(dataDir, 'label.txt')));
siteDir = dataDir;
pointer = fullfile(dataDir,'spectrum_snapshot.txt');
if isfile(pointer)
    snapshot = strtrim(fileread(pointer));
    if isempty(regexp(snapshot,'^kca-[a-zA-Z0-9_-]+$','once')) || ...
            ~isfile(fullfile(dataDir,snapshot,'site_sources.csv'))
        error('gunja:snapshot','Invalid or incomplete Spectrum Portal snapshot.');
    end
    siteDir = fullfile(dataDir,snapshot);
    map.snapshot = snapshot;
end
siteRows = csvRows(fullfile(siteDir, 'sites.csv'), ...
    {'site_id','role','east_m','north_m','azimuth_deg'});
map.siteId = siteRows(:,1);
map.role = siteRows(:,2);
coordinates = str2double(siteRows(:,3:5));
if any(~isfinite(coordinates(:))) || numel(unique(map.siteId)) ~= numel(map.siteId)
    error('gunja:sites', 'Site IDs must be unique and site coordinates and bearings finite.');
end
map.siteXY = coordinates(:,1:2);
map.azimuthDeg = coordinates(:,3);  % Clockwise from north for the first sector
if size(unique(map.siteXY, 'rows'), 1) ~= numel(map.siteId)
    error('gunja:sites', 'Each site must have a distinct position. One row represents three sectors.');
end
if ~all(ismember(map.role, {'service','external','candidate'})) || ...
        ~any(strcmp(map.role,'service')) || sum(strcmp(map.role,'candidate')) < 2
    error('gunja:roles', 'Use service, external or candidate. At least one service site and two candidates are needed.');
end

map.eastM = cfg.eastLimitsM(1):cfg.gridStepM:cfg.eastLimitsM(2);
map.northM = cfg.northLimitsM(1):cfg.gridStepM:cfg.northLimitsM(2);
[east, north] = meshgrid(map.eastM, map.northM);
map.xy = [east(:), north(:)];
map.gridSize = size(east);
map.indoor = false(numel(east),1);

vertices = csvRows(fullfile(dataDir, 'buildings.csv'), {'building_id','east_m','north_m'});
buildingIds = unique(vertices(:,1), 'stable');
map.buildings = cell(numel(buildingIds),1);
map.courtyards = cell(0,1);
holePath = fullfile(dataDir,'building_holes.csv');
holeRows = cell(0,4);
if isfile(holePath)
    holeRows = csvRows(holePath,{'building_id','hole_id','east_m','north_m'});
    if ~all(ismember(holeRows(:,1),buildingIds))
        error('gunja:polygon','A courtyard refers to an unknown building.');
    end
end
for b = 1:numel(buildingIds)
    id = buildingIds{b};
    ring = readRing(vertices(strcmp(vertices(:,1),id),2:3),id);
    map.buildings{b} = ring;
    near = find(all(map.xy >= min(ring,[],1) & map.xy <= max(ring,[],1),2));
    xy = map.xy(near,:);
    inside = inpolygon(xy(:,1),xy(:,2),ring(:,1),ring(:,2));
    holes = holeRows(strcmp(holeRows(:,1),id),:);
    ids = unique(holes(:,2));
    for h = 1:numel(ids)
        hole = readRing(holes(strcmp(holes(:,2),ids{h}),3:4),id);
        map.courtyards{end+1,1} = hole;
        [inHole,wall] = inpolygon(xy(:,1),xy(:,2),hole(:,1),hole(:,2));
        inside = inside & (~inHole | wall);
    end
    map.indoor(near(inside)) = true;
end
end

function ring = readRing(fields,id)
ring = str2double(fields);
if any(~isfinite(ring(:))) || size(unique(ring,'rows'),1) < 3 || polyarea(ring(:,1),ring(:,2)) == 0
    error('gunja:polygon','Invalid building ring: %s',id);
end
end

function rows = csvRows(path, header)
% Small, plain CSV files: reject shifted or missing fields before simulating.
lines = regexp(strtrim(fileread(path)), '\r\n|\n|\r', 'split');
if ~strcmp(strtrim(lines{1}),strjoin(header,','))
    error('gunja:header', 'Expected header in %s: %s', path, strjoin(header,','));
end
lines = lines(2:end);
lines = lines(~cellfun(@(line) isempty(strtrim(line)), lines));
rows = cell(numel(lines),numel(header));
for i = 1:numel(lines)
    fields = strtrim(strsplit(lines{i}, ',', 'CollapseDelimiters', false));
    if numel(fields) ~= numel(header) || any(cellfun(@isempty,fields))
        error('gunja:csv', 'Incomplete CSV row in %s: %s', path, lines{i});
    end
    rows(i,:) = fields;
end
end
