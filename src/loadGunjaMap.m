function map = loadGunjaMap(dataDir, cfg)
% Load site roles and building rings in local metres, east/north of the origin.
map.label = strtrim(fileread(fullfile(dataDir, 'label.txt')));
siteRows = csvRows(fullfile(dataDir, 'sites.csv'), ...
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
for b = 1:numel(buildingIds)
    ring = str2double(vertices(strcmp(vertices(:,1),buildingIds{b}), 2:3));
    if any(~isfinite(ring(:))) || size(unique(ring,'rows'),1) < 3 || polyarea(ring(:,1),ring(:,2)) == 0
        error('gunja:polygon', 'Invalid building polygon: %s', buildingIds{b});
    end
    map.buildings{b} = ring;
    map.indoor = map.indoor | inpolygon(map.xy(:,1),map.xy(:,2),ring(:,1),ring(:,2));
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
