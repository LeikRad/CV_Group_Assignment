class Shape:
    def __init__(
        self, position, size, colour, shapeType, operation, blendStrength, numChildren
    ):
        self.position = position
        self.size = size
        self.colour = colour
        self.shapeType = shapeType
        self.operation = operation
        self.blendStrength = blendStrength
        self.numChildren = numChildren
