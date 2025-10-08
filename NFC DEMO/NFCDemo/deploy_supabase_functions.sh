#!/bin/bash

# =========================================
# Supabase Functions Deployment Script
# =========================================
# 
# This script deploys the enhanced SQL functions to your Supabase database
# Make sure you have the Supabase CLI installed and configured
#
# Usage: ./deploy_supabase_functions.sh
#

set -e  # Exit on any error

echo "🚀 Starting Supabase Functions Deployment..."

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Please install it first:"
    echo "   npm install -g supabase"
    echo "   or"
    echo "   brew install supabase/tap/supabase"
    exit 1
fi

# Check if we're in a Supabase project
if [ ! -f "supabase/config.toml" ]; then
    echo "⚠️  Not in a Supabase project directory. Initializing..."
    echo "📝 Please run 'supabase init' first, then configure your project."
    echo ""
    echo "Steps to set up:"
    echo "1. supabase init"
    echo "2. supabase login"
    echo "3. supabase link --project-ref YOUR_PROJECT_REF"
    echo "4. Run this script again"
    exit 1
fi

# Get the SQL file path
SQL_FILE="supabase_enhanced_functions.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo "❌ SQL file not found: $SQL_FILE"
    echo "   Please make sure the file exists in the current directory"
    exit 1
fi

echo "📁 Found SQL file: $SQL_FILE"

# Method 1: Using supabase db push (recommended for development)
echo ""
echo "🔄 Deploying functions using Supabase CLI..."
echo ""

# Create a migration file
TIMESTAMP=$(date +%Y%m%d%H%M%S)
MIGRATION_FILE="supabase/migrations/${TIMESTAMP}_enhanced_functions.sql"

# Copy the SQL file to migrations
cp "$SQL_FILE" "$MIGRATION_FILE"

echo "📝 Created migration file: $MIGRATION_FILE"

# Apply the migration
echo "🚀 Applying migration to database..."
supabase db push

echo ""
echo "✅ Functions deployed successfully!"
echo ""

# Test the deployment
echo "🧪 Testing function deployment..."

# Test haversine distance function
echo "Testing haversine_distance function..."
supabase db query "SELECT haversine_distance(40.7128, -74.0060, 40.7589, -73.9851) as distance_meters;" || echo "⚠️  Function test failed - this is normal if tables don't exist yet"

echo ""
echo "🎉 Deployment completed!"
echo ""
echo "📋 Available functions:"
echo "   • haversine_distance(lat1, lon1, lat2, lon2)"
echo "   • get_gate_scan_counts(event_id)"
echo "   • get_event_categories(event_id)"
echo "   • find_nearby_gates_by_category(lat, lon, event_id, category, radius)"
echo "   • process_unlinked_checkins(event_id, batch_limit)"
echo "   • get_event_stats_comprehensive(event_id)"
echo "   • auto_link_checkin_to_gate() [trigger function]"
echo ""
echo "📊 Available views:"
echo "   • checkin_logs_with_category"
echo "   • event_category_stats"
echo "   • unlinked_checkins_with_category"
echo ""
echo "💡 To enable automatic gate linking, run:"
echo "   supabase db query \"CREATE TRIGGER trigger_auto_link_checkin BEFORE INSERT ON checkin_logs FOR EACH ROW EXECUTE FUNCTION auto_link_checkin_to_gate();\""
echo ""
echo "🔍 To test with your data, replace 'your-event-id' in the test queries with actual event IDs"
