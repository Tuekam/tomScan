import torch
import torch.nn as nn
from torchvision import models
from PIL import Image
import io
from ml.class_names import CLASS_NAMES
from ml.transforms import get_transform
from app.core.config import settings

class IAService:
    def __init__(self, model_path: str):
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.class_names = CLASS_NAMES
        self.transform = get_transform()
        self.seuil = settings.SEUIL_CONFIANCE_RESNET  # ← Centralisé
        self.model = self._load_model(model_path)

    def _load_model(self, model_path: str):
        """
        Charge le modèle en supportant à la fois TorchScript et state_dict
        """
        try:
            # ✅ 1. Essayer de charger en TorchScript (nouveau modèle)
            model = torch.jit.load(model_path, map_location=self.device)
            print(f"✅ Modèle chargé en mode TorchScript avec {len(self.class_names)} classes")
            model = model.to(self.device)
            model.eval()
            return model
        except Exception as e:
            print(f"⚠️ Échec chargement TorchScript: {e}")
            
            # ✅ 2. Fallback: charger en state_dict (ancien modèle)
            try:
                model = models.resnet18(pretrained=False)
                num_ftrs = model.fc.in_features
                model.fc = nn.Linear(num_ftrs, len(self.class_names))
                model.load_state_dict(torch.load(model_path, map_location=self.device, weights_only=False))
                model = model.to(self.device)
                model.eval()
                print(f"✅ Modèle chargé en mode state_dict avec {len(self.class_names)} classes")
                return model
            except Exception as e2:
                print(f"❌ Erreur chargement modèle: {e2}")
                raise RuntimeError(f"Impossible de charger le modèle: {e2}")

    async def classifier(self, image_bytes: bytes):
        image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
        tensor = self.transform(image).unsqueeze(0).to(self.device)

        with torch.no_grad():
            outputs = self.model(tensor)
            # ✅ Support TorchScript et state_dict
            if hasattr(outputs, 'shape') and len(outputs.shape) == 2:
                probs = torch.nn.functional.softmax(outputs[0], dim=0)
            else:
                probs = torch.nn.functional.softmax(outputs, dim=0)
            conf, pred = torch.max(probs, 0)

        maladie = self.class_names[pred.item()]
        confiance = conf.item() * 100

        if confiance < self.seuil:
            maladie = "Non identifiable"

        return maladie, confiance