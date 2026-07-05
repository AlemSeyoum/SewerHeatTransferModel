function [b, Larc] = geom_egg(R, Dw)
%GEOM_EGG  Approximate egg-shaped conduit geometry
%   R  = characteristic radius [m]
%   Dw = water depth [m]

Dw = max(Dw, 1e-9);
Dw = min(Dw, 2*R - 1e-9);

% Approximate egg as modified circle (engineering surrogate)
if Dw <= R
    theta = acos((R - Dw)/R);
    b     = 2*R*sin(theta);
    Larc  = 2*R*theta;
else
    theta = acos((Dw - R)/R);
    b     = 2*R*sin(theta);
    Larc  = 2*pi*R - 2*R*theta;
end
end
