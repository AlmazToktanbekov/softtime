#!/bin/bash
# SoftTime Project - Production Deployment Script
# Purpose: Quick start guide for deployment
# Date: May 11, 2026

set -e

echo "🚀 SoftTime Production Deployment Helper"
echo "========================================"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found${NC}"
    echo "Install from: https://docker.com"
    exit 1
fi
echo -e "${GREEN}✅ Docker installed${NC}"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose not found${NC}"
    echo "Install from: https://docker.com/products/docker-desktop"
    exit 1
fi
echo -e "${GREEN}✅ Docker Compose installed${NC}"

# Check Flutter (optional)
if command -v flutter &> /dev/null; then
    echo -e "${GREEN}✅ Flutter installed${NC}"
else
    echo -e "${YELLOW}⚠️  Flutter not found (required for mobile app build)${NC}"
fi

echo ""
echo "📦 Deployment Options"
echo "===================="
echo ""
echo "1️⃣  Deploy Backend + Database (Docker)"
echo "2️⃣  Test on local machine"
echo "3️⃣  Deploy to production server"
echo ""
echo -e "${YELLOW}Before proceeding:${NC}"
echo "✅ Copy .env.prod.example → .env.prod"
echo "✅ Edit .env.prod with your values"
echo "✅ Download Firebase service account JSON"
echo ""
echo "Quick start:"
echo "  ./deploy.sh 1  # Deploy backend locally"
echo ""

# If argument provided
case "$1" in
    1)
        echo "🔧 Starting local backend deployment..."
        echo ""
        
        # Check .env.prod exists
        if [ ! -f ".env.prod" ]; then
            echo -e "${RED}❌ .env.prod not found${NC}"
            echo "Copy from: .env.prod.example"
            cp .env.prod.example .env.prod
            echo -e "${YELLOW}Created .env.prod - please edit with your values${NC}"
            exit 1
        fi
        
        # Check Firebase file
        if [ ! -f "backend/firebase-adminsdk.json" ]; then
            echo -e "${YELLOW}⚠️  Firebase service account not found${NC}"
            echo "Download from Firebase Console and place at:"
            echo "  backend/firebase-adminsdk.json"
        fi
        
        echo "Starting Docker services..."
        docker-compose -f docker-compose.prod.full.yml up -d
        
        echo ""
        echo -e "${GREEN}✅ Services starting...${NC}"
        echo ""
        echo "Waiting for database to be ready..."
        sleep 10
        
        echo ""
        echo "🔄 Running database migrations..."
        docker-compose -f docker-compose.prod.full.yml exec -T backend \
            alembic upgrade head
        
        echo ""
        echo -e "${GREEN}✅ Deployment complete!${NC}"
        echo ""
        echo "Services:"
        echo "  • Backend API:     http://localhost:8000"
        echo "  • API Docs:        http://localhost:8000/docs"
        echo "  • Admin Web:       http://localhost"
        echo "  • PostgreSQL:      localhost:5432"
        echo "  • Redis:           localhost:6379"
        echo ""
        echo "Check status: docker-compose ps"
        echo "View logs:   docker-compose logs backend"
        echo ""
        ;;
    
    2)
        echo "🧪 Testing backend locally..."
        echo ""
        
        if [ ! -d "backend" ]; then
            echo -e "${RED}❌ backend directory not found${NC}"
            exit 1
        fi
        
        cd backend
        echo "Running tests..."
        python3 -m pytest tests/ -v
        
        echo ""
        echo -e "${GREEN}✅ Tests complete${NC}"
        cd ..
        ;;
    
    3)
        echo "📤 Production deployment helper"
        echo ""
        echo "Before deployment to production server:"
        echo ""
        echo "1. Update DNS to point to server IP"
        echo "2. Generate SSL certificate:"
        echo "     certbot certonly --standalone -d your-domain.com"
        echo "3. Update docker-compose.prod.full.yml with:"
        echo "     - BACKEND_DOMAIN=your-domain.com"
        echo "     - Nginx SSL paths"
        echo ""
        echo "Then run on server:"
        echo "     ./deploy.sh 1"
        echo ""
        echo "See DEPLOYMENT.md for detailed instructions"
        ;;
    
    *)
        echo "Usage: ./deploy.sh [1|2|3]"
        echo ""
        echo "Options:"
        echo "  1 - Deploy backend locally"
        echo "  2 - Run tests"
        echo "  3 - Show production deployment guide"
        echo ""
        ;;
esac
