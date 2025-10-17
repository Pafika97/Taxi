from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from sqlalchemy import create_engine, Column, Integer, String, DateTime, Float, ForeignKey
from sqlalchemy.orm import declarative_base, sessionmaker, relationship, Session

# === Database setup ===
engine = create_engine("sqlite:///taxi.db", echo=False, future=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)
Base = declarative_base()

class RideRequest(Base):
    __tablename__ = "ride_requests"
    id = Column(Integer, primary_key=True, index=True)
    pickup = Column(String, nullable=False)
    dropoff = Column(String, nullable=False)
    passenger_name = Column(String, nullable=True)
    status = Column(String, default="open")  # open | assigned | completed | cancelled
    created_at = Column(DateTime, default=datetime.utcnow)
    accepted_offer_id = Column(Integer, ForeignKey("offers.id"), nullable=True)

    offers = relationship("Offer", back_populates="request", cascade="all, delete-orphan")

class Offer(Base):
    __tablename__ = "offers"
    id = Column(Integer, primary_key=True, index=True)
    request_id = Column(Integer, ForeignKey("ride_requests.id"))
    driver_name = Column(String, nullable=False)
    price = Column(Float, nullable=False)
    eta_minutes = Column(Integer, nullable=False)
    status = Column(String, default="pending")  # pending | accepted | rejected
    created_at = Column(DateTime, default=datetime.utcnow)

    request = relationship("RideRequest", back_populates="offers")

Base.metadata.create_all(engine)

# === Pydantic models ===
class CreateRequestIn(BaseModel):
    pickup: str
    dropoff: str
    passenger_name: Optional[str] = None

class RequestOut(BaseModel):
    id: int
    pickup: str
    dropoff: str
    passenger_name: Optional[str] = None
    status: str
    accepted_offer_id: Optional[int] = None
    created_at: datetime

    class Config:
        from_attributes = True

class OfferIn(BaseModel):
    request_id: int
    driver_name: str
    price: float
    eta_minutes: int

class OfferOut(BaseModel):
    id: int
    request_id: int
    driver_name: str
    price: float
    eta_minutes: int
    status: str
    created_at: datetime

    class Config:
        from_attributes = True

class AcceptOfferIn(BaseModel):
    offer_id: int

# === FastAPI app ===
app = FastAPI(title="Taxi Bid Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/health")
def health():
    return {"ok": True}

@app.post("/requests", response_model=RequestOut)
def create_request(body: CreateRequestIn, db: Session = Depends(get_db)):
    r = RideRequest(
        pickup=body.pickup.strip(),
        dropoff=body.dropoff.strip(),
        passenger_name=(body.passenger_name or "").strip() or None,
    )
    db.add(r)
    db.commit()
    db.refresh(r)
    return r

@app.get("/requests", response_model=List[RequestOut])
def list_requests(status: Optional[str] = None, db: Session = Depends(get_db)):
    q = db.query(RideRequest)
    if status:
        q = q.filter(RideRequest.status == status)
    q = q.order_by(RideRequest.created_at.desc())
    return q.all()

@app.get("/requests/{request_id}", response_model=RequestOut)
def get_request(request_id: int, db: Session = Depends(get_db)):
    r = db.get(RideRequest, request_id)
    if not r:
        raise HTTPException(404, "Request not found")
    return r

@app.get("/requests/{request_id}/offers", response_model=List[OfferOut])
def list_offers(request_id: int, db: Session = Depends(get_db)):
    r = db.get(RideRequest, request_id)
    if not r:
        raise HTTPException(404, "Request not found")
    return (
        db.query(Offer)
        .filter(Offer.request_id == request_id)
        .order_by(Offer.price.asc(), Offer.created_at.asc())
        .all()
    )

@app.post("/offers", response_model=OfferOut)
def create_offer(body: OfferIn, db: Session = Depends(get_db)):
    r = db.get(RideRequest, body.request_id)
    if not r or r.status != "open":
        raise HTTPException(400, "Request is not open or doesn't exist")
    o = Offer(
        request_id=body.request_id,
        driver_name=body.driver_name.strip(),
        price=float(body.price),
        eta_minutes=int(body.eta_minutes),
    )
    db.add(o)
    db.commit()
    db.refresh(o)
    return o

@app.post("/requests/{request_id}/accept")
def accept_offer(request_id: int, body: AcceptOfferIn, db: Session = Depends(get_db)):
    r = db.get(RideRequest, request_id)
    if not r or r.status != "open":
        raise HTTPException(400, "Request is not open or doesn't exist")
    o = db.get(Offer, body.offer_id)
    if not o or o.request_id != request_id:
        raise HTTPException(400, "Offer doesn't match request")

    # mark accepted and update others
    o.status = "accepted"
    r.status = "assigned"
    r.accepted_offer_id = o.id
    db.query(Offer).filter(Offer.request_id == request_id, Offer.id != o.id).update(
        {Offer.status: "rejected"}, synchronize_session=False
    )
    db.commit()
    return {"ok": True, "request_id": r.id, "accepted_offer_id": o.id}

@app.post("/requests/{request_id}/complete")
def complete_request(request_id: int, db: Session = Depends(get_db)):
    r = db.get(RideRequest, request_id)
    if not r:
        raise HTTPException(404, "Request not found")
    r.status = "completed"
    db.commit()
    return {"ok": True}
