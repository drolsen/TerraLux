local Corners = {}

function Corners.make(p, r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=p; return c end

return Corners
