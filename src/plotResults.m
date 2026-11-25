function plotResults(outputDir, map, cfg, plan, results)
% Render figures without opening windows; use a single dB scale for all SINR maps.
drawLayout(outputDir,map,plan);
base35 = results{1,1};
base28 = results{2,1};
wide = results{3,1};
added = results{3,2};
frequencyLabels = {'3.5 GHz / 100 MHz','28 GHz / 100 MHz'};
layoutLabels = {'28 GHz / 800 MHz, baseline','28 GHz / 800 MHz, two sites added'};
drawMapPair(outputDir,'frequency_sinr.png',map,cfg,{base35,base28},frequencyLabels,{[],[]});
drawMapPair(outputDir,'placement_sinr.png',map,cfg,{wide,added},layoutLabels,{[],plan.added});
drawChangeMap(outputDir,map,plan,wide,added);
drawCdfPair(outputDir,'bandwidth_cdf.png',map,{base35,wide},{'3.5 GHz / 100 MHz','28 GHz / 800 MHz'});
drawCdfPair(outputDir,'placement_cdf.png',map,{wide,added},layoutLabels);
end

function drawLayout(outputDir,map,plan)
fig = newFigure(900,640);
hold on;
drawBuildings(map,true);
boundsX = map.eastM([1,end,end,1,1]);
boundsY = map.northM([1,1,end,end,1]);
plot(boundsX,boundsY,'k--','LineWidth',1,'DisplayName','Evaluation area');
otherCandidates = setdiff(find(strcmp(map.role,'candidate')),plan.added);
markSites(map,find(strcmp(map.role,'service')),'^',[0.05 0.35 0.65],'Service');
markSites(map,find(strcmp(map.role,'external')),'s',[0.46 0.18 0.18],'External interference');
markSites(map,otherCandidates,'o',[0.45 0.45 0.45],'Other candidates');
markSites(map,plan.added,'p',[0.12 0.55 0.28],'Selected pair');
for s = 1:numel(map.siteId)
    text(map.siteXY(s,1)+7,map.siteXY(s,2)+7,map.siteId{s}, ...
        'FontSize',9,'Interpreter','none','Clipping','on');
end
axis equal;
axis([min([boundsX(:);map.siteXY(:,1)])-35,max([boundsX(:);map.siteXY(:,1)])+45, ...
      min([boundsY(:);map.siteXY(:,2)])-35,max([boundsY(:);map.siteXY(:,2)])+35]);
box on;
xlabel('East (m)'); ylabel('North (m)');
title(map.label,'Interpreter','none');
legend('Location','eastoutside');
saveFigure(fig,outputDir,'layout.png');
end

function drawMapPair(outputDir,name,map,cfg,results,labels,additions)
fig = newFigure(1180,540);
colors = [0.12 0.12 0.31;0.15 0.30 0.53;0.11 0.53 0.55;0.44 0.74 0.47;0.99 0.91 0.36];
set(fig,'Colormap',interp1(linspace(0,1,size(colors,1)),colors,linspace(0,1,256)));
for k = 1:2
    subplot(1,2,k);
    fieldDb = reshape(median(results{k}.sinrDb,2),map.gridSize);
    imagesc(map.eastM,map.northM,fieldDb);
    axis xy; axis image;
    caxis(cfg.sinrColorLimitsDb);
    hold on;
    drawBuildings(map,false);
    markSites(map,find(strcmp(map.role,'service')),'^',[1 1 1],'Service');
    markSites(map,additions{k},'p',[1 0.60 0.14],'Added');
    xlim(map.eastM([1,end])); ylim(map.northM([1,end]));
    xlabel(['East (m)  |  ' map.label],'Interpreter','none'); ylabel('North (m)');
    title([labels{k} '  |  Median SINR (dB)'],'Interpreter','none');
    colorbar;
end
saveFigure(fig,outputDir,name);
end

function drawChangeMap(outputDir,map,plan,before,after)
fig = newFigure(820,650);
changeDb = reshape(median(after.sinrDb-before.sinrDb,2),map.gridSize);
imagesc(map.eastM,map.northM,changeDb);
axis xy; axis image; hold on;
colors = [0.71 0.21 0.09;0.97 0.96 0.93;0.06 0.40 0.48];
colormap(interp1([-1,0,1],colors,linspace(-1,1,255)));
caxis([-15,15]); colorbar;
drawBuildings(map,false);
markSites(map,plan.added,'p',[1 0.69 0.08],'Added');
xlim(map.eastM([1,end])); ylim(map.northM([1,end]));
xlabel(['East (m)  |  ' map.label],'Interpreter','none'); ylabel('North (m)');
title('28 GHz / 800 MHz  |  Median of paired SINR changes (dB)');
saveFigure(fig,outputDir,'placement_change.png');
end

function drawCdfPair(outputDir,name,map,results,labels)
groups = {true(size(map.indoor)),map.indoor};
headings = {'All grid points','Indoor grid points'};
colors = [0.12 0.37 0.64;0.70 0.26 0.10];
nPanels = 1 + any(map.indoor);
fig = newFigure(570*nPanels,510);
for g = 1:nPanels
    subplot(1,nPanels,g);
    hold on;
    for k = 1:2
        rates = results{k}.rateMbps(groups{g},:);
        ordered = sort(rates(:));
        n = numel(ordered);
        % Draw at most 1001 ranks per curve; CSV statistics use every sample.
        idx = unique(round(linspace(1,n,min(n,1001))));
        plot(ordered(idx),idx(:)/n,'Color',colors(k,:),'LineWidth',1.8,'DisplayName',labels{k});
    end
    set(gca,'XScale','log');
    xBounds = xlim;
    for q = [0.05,0.5]
        line(xBounds,[q q],'LineStyle',':','Color',[0.4 0.4 0.4],'HandleVisibility','off');
    end
    legend('Location','northwest');
    ylim([0,1]); grid on; box on;
    xlabel('Shannon rate (Mbps, log scale)'); ylabel('Cumulative fraction');
    title([headings{g} '  |  ' map.label],'Interpreter','none');
end
saveFigure(fig,outputDir,name);
end

function drawBuildings(map,fillShapes)
for b = 1:numel(map.buildings)
    ring = map.buildings{b};
    if fillShapes
        patch(ring(:,1),ring(:,2),[0.88 0.90 0.91],'EdgeColor',[0.64 0.68 0.70],'HandleVisibility','off');
    else
        ring = ring([1:end,1],:);
        plot(ring(:,1),ring(:,2),'-','Color',[0.85 0.87 0.91],'LineWidth',0.6,'HandleVisibility','off');
    end
end
end

function markSites(map,indices,marker,color,label)
if isempty(indices), return; end
plot(map.siteXY(indices,1),map.siteXY(indices,2),marker,'LineStyle','none', ...
    'MarkerEdgeColor',[0.12 0.14 0.16],'MarkerFaceColor',color,'MarkerSize',9,'DisplayName',label);
end

function fig = newFigure(width,height)
fig = figure('Visible','off','Color','white','Units','pixels','Position',[50,50,width,height], ...
    'PaperPositionMode','auto');
end

function saveFigure(fig,outputDir,name)
guard = onCleanup(@() close(fig)); %#ok<NASGU>
print(fig,fullfile(outputDir,name),'-dpng','-r125');
end
