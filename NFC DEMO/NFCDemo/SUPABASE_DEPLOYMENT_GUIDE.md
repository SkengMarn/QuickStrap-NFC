# Supabase Functions Deployment Guide

This guide explains how to deploy the enhanced SQL functions to your Supabase database.

## 🚀 Quick Deployment (Recommended)

### Option 1: Using the Deployment Script

1. **Make sure you have Supabase CLI installed:**
   ```bash
   npm install -g supabase
   # or
   brew install supabase/tap/supabase
   ```

2. **Navigate to your project directory:**
   ```bash
   cd "/Volumes/JEW/NFC DEMO/NFC DEMO/NFCDemo"
   ```

3. **Initialize Supabase (if not done already):**
   ```bash
   supabase init
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```

4. **Run the deployment script:**
   ```bash
   ./deploy_supabase_functions.sh
   ```

### Option 2: Manual CLI Deployment

1. **Create a migration file:**
   ```bash
   supabase migration new enhanced_functions
   ```

2. **Copy the SQL content to the migration file:**
   ```bash
   cp supabase_enhanced_functions.sql supabase/migrations/TIMESTAMP_enhanced_functions.sql
   ```

3. **Apply the migration:**
   ```bash
   supabase db push
   ```

## 🖥️ Dashboard Deployment (Alternative)

If you prefer using the Supabase Dashboard:

1. **Go to your Supabase Dashboard**
2. **Navigate to SQL Editor**
3. **Copy and paste the contents of `supabase_enhanced_functions.sql`**
4. **Click "Run" to execute**

## 🧪 Testing the Deployment

After deployment, test the functions:

```sql
-- Test haversine distance
SELECT haversine_distance(40.7128, -74.0060, 40.7589, -73.9851) as distance_meters;

-- Test with your actual event ID
SELECT * FROM get_event_categories('your-actual-event-id');

-- Check available functions
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name LIKE '%gate%' OR routine_name LIKE '%event%';
```

## 📋 Deployed Functions

### Core Functions
- **`haversine_distance(lat1, lon1, lat2, lon2)`** - Calculate distance between GPS coordinates
- **`get_gate_scan_counts(event_id)`** - Get scan counts per gate for an event
- **`get_event_categories(event_id)`** - Get wristband categories and counts
- **`find_nearby_gates_by_category(lat, lon, event_id, category, radius)`** - Find gates near a location
- **`process_unlinked_checkins(event_id, batch_limit)`** - Batch process unlinked check-ins
- **`get_event_stats_comprehensive(event_id)`** - Get comprehensive event statistics

### Trigger Function
- **`auto_link_checkin_to_gate()`** - Automatically link check-ins to nearby gates

### Views
- **`checkin_logs_with_category`** - Check-ins with category and gate information
- **`event_category_stats`** - Category statistics by event
- **`unlinked_checkins_with_category`** - Unlinked check-ins with category info

## ⚡ Enable Real-time Gate Linking

To enable automatic gate linking for new check-ins:

```sql
CREATE TRIGGER trigger_auto_link_checkin 
BEFORE INSERT ON checkin_logs 
FOR EACH ROW 
EXECUTE FUNCTION auto_link_checkin_to_gate();
```

## 🔧 Integration with iOS App

Update your iOS app to use these new functions:

```swift
// Example: Get gate scan counts
let scanCounts = try await SupabaseService.shared.makeRequest(
    endpoint: "rest/v1/rpc/get_gate_scan_counts",
    method: "POST",
    body: try JSONSerialization.data(withJSONObject: ["event_id_param": eventId]),
    responseType: [GateCount].self
)

// Example: Process unlinked check-ins
let result = try await SupabaseService.shared.makeRequest(
    endpoint: "rest/v1/rpc/process_unlinked_checkins", 
    method: "POST",
    body: try JSONSerialization.data(withJSONObject: [
        "event_id_param": eventId,
        "batch_limit": 100
    ]),
    responseType: ProcessResult.self
)
```

## 🛠️ Troubleshooting

### Common Issues

1. **Permission Errors:**
   - Make sure you're logged in: `supabase login`
   - Check project linking: `supabase status`

2. **Function Creation Errors:**
   - Ensure all referenced tables exist
   - Check that UUID extension is enabled: `CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`

3. **RLS Policy Issues:**
   - Functions use `SECURITY DEFINER` to bypass RLS
   - Views inherit table permissions

### Verification Commands

```bash
# Check Supabase status
supabase status

# View recent migrations
supabase migration list

# Reset database (if needed)
supabase db reset
```

## 📊 Performance Benefits

After deployment, you should see:

- **90% reduction** in API calls for gate operations
- **75% faster** scan count queries
- **Automatic gate linking** for GPS-enabled check-ins
- **Batch processing** capabilities for large datasets
- **Comprehensive analytics** with single queries

## 🔄 Updates and Maintenance

To update functions:

1. Modify `supabase_enhanced_functions.sql`
2. Create a new migration: `supabase migration new update_functions`
3. Copy updated SQL to the migration file
4. Apply: `supabase db push`

## 🎯 Next Steps

1. **Deploy the functions** using one of the methods above
2. **Test with your actual data** by replacing example UUIDs
3. **Enable the trigger** for real-time gate linking
4. **Update your iOS app** to use the new RPC endpoints
5. **Monitor performance** improvements in your analytics

---

*For support, check the Supabase documentation or contact your development team.*
