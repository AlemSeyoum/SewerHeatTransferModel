%{

function Rws = Rwsfun(t, kp, Larc, dL, ksds, b)

    % Force column vectors
    t    = t(:);
    kp   = kp(:);
    Larc = Larc(:);
    dL   = dL(:);
    ksds = ksds(:);
    b    = b(:);

    wallTerm = t ./ (kp .* Larc .* dL);
    soilTerm = 1 ./ (ksds .* b .* dL);

    Rws = wallTerm + soilTerm;
end

%}
function Rws = Rwsfun(t, kp, Larc, dL, ksds, b)

    t    = t(:);
    kp   = kp(:);
    Larc = Larc(:);
    ksds = ksds(:);
    dL   = dL(:);
    b    = b(:);
    wallTerm = t ./ (kp .* Larc .* dL);
    soilTerm = 1 ./ (ksds .* Larc .* dL);

    Rws = wallTerm + soilTerm;
end