import httpx
from app.core.config import settings

class MistralService:
    def __init__(self):
        self.api_key = settings.MISTRAL_API_KEY
        self.base_url = "https://api.mistral.ai/v1/chat/completions"
        self.model = "mistral-tiny"  # ou "mistral-small"

    async def ask(self, question: str, conversation_history: list = None) -> str:
        if not self.api_key:
            return "Service IA non configuré (clé API manquante)."

        messages = [
            {"role": "system", "content": "Tu es un assistant agricole Camerounais au nom de tomScan AI spécialisé dans les maladies de la tomate. Réponds de manière courte, breve, precise et concise ne detaille pas.repond dans le contexte agricole camerounais. si une question n'est pas dans le contexte de la tomate tu repond simplement que votre question est hors contexte "}
        ]
        if conversation_history:
            messages.extend(conversation_history)
        messages.append({"role": "user", "content": question})

        async with httpx.AsyncClient() as client:
            try:
                response = await client.post(
                    self.base_url,
                    headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                    json={
                        "model": self.model,
                        "messages": messages,
                        "temperature": 0.7,
                        "max_tokens": 500
                    },
                    timeout=30.0
                )
                if response.status_code == 200:
                    return response.json()["choices"][0]["message"]["content"]
                else:
                    return f"Erreur Mistral: {response.status_code} - {response.text}"
            except Exception as e:
                return f"Erreur de connexion: {str(e)}"