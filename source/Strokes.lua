local Strokes = {}

function Strokes.make(p, c, t) local s=Instance.new("UIStroke"); s.Color=c; s.Thickness=t or 1; s.Parent=p; return s end

return Strokes
