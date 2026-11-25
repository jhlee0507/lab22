function values = samplePercentile(samples, percent)
% Inverse empirical CDF: the smallest observation reaching the requested fraction.
if isempty(samples)
    values = nan(size(percent));
    return;
end
ordered = sort(samples(:));
rank = max(1,ceil(numel(ordered)*percent/100));
values = reshape(ordered(rank), size(percent));
end
