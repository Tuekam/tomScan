from pydantic import BaseModel
from typing import Optional

class PredictRequest(BaseModel):
    latitude: float
    longitude: float
    precision_gps: Optional[float] = 0.0