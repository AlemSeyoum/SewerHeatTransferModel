function [b, Larc] = geom_circle(R, Dw)
%GEOM_CIRCLE  Wetted top width and wetted perimeter for circular pipe
%   R  = radius [m]
%   Dw = water depth [m]
R = max(R, 1e-9);
Dw = max(Dw, 1e-9);
Dw = min(Dw, 2*R - 1e-9);

if Dw <= R
    theta = acos((R - Dw)/R);   % radians
    b     = 2*R*sin(theta);
    Larc  = 2*R*theta;
else
    theta = acos((Dw - R)/R);
    b     = 2*R*sin(theta);
    Larc  = 2*pi*R - 2*R*theta;
end
end
