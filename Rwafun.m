%{
function Rwa = Rwafun(hwa, b, dL)

    % Force column vectors (one value per pipe)
    hwa = hwa(:);
    b   = b(:);
    dL  = dL(:);

    Rwa = 1 ./ (hwa .* b .* dL);
end
%}

function Rwa = Rwafun(hwa, b, dL)

    % hwa : water-air heat transfer coefficient [W/m^2/K]
    % b   : free-surface top width [m]
    % dL  : segment length [m]

    hwa = hwa(:);
    b   = b(:);
    dL  = dL(:);

    Rwa = inf(size(b));
    idx = b > 0;

    Rwa(idx) = 1 ./ (hwa(idx) .* b(idx) .* dL(idx));
end