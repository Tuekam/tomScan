import torch
import torch.nn as nn
from torchvision import models
from PIL import Image
import io
from ml.class_names import CLASS_NAMES
from ml.transforms import get_transform

class IAService:
    def __init__(self, model_path: str):
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.class_names = CLASS_NAMES  # ← Défini AVANT d'appeler _load_model
        self.transform = get_transform()
        self.seuil = 50.0
        self.model = self._load_model(model_path)

    def _load_model(self, model_path: str):
        model = models.resnet18(pretrained=False)
        num_ftrs = model.fc.in_features
        model.fc = nn.Linear(num_ftrs, len(self.class_names))  # ← maintenant self.class_names existe
        model.load_state_dict(torch.load(model_path, map_location=self.device))
        model = model.to(self.device)
        model.eval()
        return model

    async def classifier(self, image_bytes: bytes):
        image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        tensor = self.transform(image).unsqueeze(0).to(self.device)

        with torch.no_grad():
            outputs = self.model(tensor)
            probs = torch.nn.functional.softmax(outputs[0], dim=0)
            conf, pred = torch.max(probs, 0)

        maladie = self.class_names[pred.item()]
        confiance = conf.item() * 100

        if confiance < self.seuil:
            maladie = "Non identifiable"

        return maladie, confiance