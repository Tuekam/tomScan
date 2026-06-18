from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from typing import List, Optional
from app.repositories.conversation_repository import ConversationRepository
from app.services.mistral_service import MistralService

router = APIRouter()
conv_repo = ConversationRepository()
mistral = MistralService()

class NewConversationRequest(BaseModel):
    sujet: Optional[str] = None

class SendMessageRequest(BaseModel):
    question: str

@router.post("/conversations")
async def create_conversation(req: NewConversationRequest, user_id: int = 1):
    conv_id = await conv_repo.create_conversation(user_id, req.sujet)
    return {"id": conv_id, "sujet": req.sujet or "Nouvelle conversation"}

@router.get("/conversations")
async def list_conversations(user_id: int = 1):
    return await conv_repo.get_conversations_by_user(user_id)

@router.get("/conversations/{conv_id}/messages")
async def get_messages(conv_id: int):
    return await conv_repo.get_messages(conv_id)

@router.post("/conversations/{conv_id}/messages")
async def send_message(conv_id: int, req: SendMessageRequest):
    # Récupérer l'historique des messages pour le contexte
    history = await conv_repo.get_messages(conv_id)
    # Formater l'historique pour Mistral
    conv_history = []
    for msg in history:
        conv_history.append({"role": "user", "content": msg["question"]})
        conv_history.append({"role": "assistant", "content": msg["reponse"]})
    # Appeler Mistral
    reponse = await mistral.ask(req.question, conv_history)
    # Sauvegarder la nouvelle interaction
    await conv_repo.add_message(conv_id, req.question, reponse)
    return {"question": req.question, "reponse": reponse}