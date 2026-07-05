function order = topo_sort_from_usLinkIndex(usLinkIndex, N)
    % Kahn topological sort (parents lists given by usLinkIndex)
    indeg = zeros(N,1);
    children = cell(N,1);

    for i = 1:N
        ups = usLinkIndex{i};
        indeg(i) = numel(ups);
        for k = 1:numel(ups)
            up = ups(k);
            children{up}(end+1) = i; %#ok<AGROW>
        end
    end

    q = find(indeg==0);
    order = zeros(1,N); p = 0;

    while ~isempty(q)
        v = q(1); q(1) = [];
        p = p + 1;
        order(p) = v;

        ch = children{v};
        for k = 1:numel(ch)
            w = ch(k);
            indeg(w) = indeg(w) - 1;
            if indeg(w)==0
                q(end+1) = w; %#ok<AGROW>
            end
        end
    end

    if p < N
        rem = setdiff(1:N, order(1:p));
        order = [order(1:p), rem];
    end
end