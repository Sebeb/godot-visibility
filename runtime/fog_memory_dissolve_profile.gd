extends Resource
class_name FogMemoryDissolveProfile

## GPU presentation settings for the soft edge of an explored-memory decay frontier.
##
## PGO-157 moves the frontier from world world units into the history texture's
## recency gradient, so the soft edge is now a width in recency rather than metres.

# Sets the half-width of the soft frontier, in recency units (0..1 over all history).
@export_range(0.0, 0.5, 0.0001) var soft_edge_recency := 0.01
