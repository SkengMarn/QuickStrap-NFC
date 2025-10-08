# QuickStrap NFC: Production Deployment Guide

## 🎯 Overview
This guide covers the complete deployment of QuickStrap NFC's fraud prevention system from development to production.

## 📋 Pre-Deployment Checklist

### ✅ Database Schema Migration
- [ ] Execute ticket linking SQL migration in Supabase
- [ ] Verify all tables created correctly (tickets, ticket_link_audit, etc.)
- [ ] Test database triggers and validation functions
- [ ] Set up proper RLS (Row Level Security) policies
- [ ] Configure database backups and monitoring

### ✅ API Configuration
- [ ] Update Supabase API endpoints for ticket operations
- [ ] Configure authentication and authorization rules
- [ ] Set up rate limiting for fraud prevention
- [ ] Test all CRUD operations for tickets and linking
- [ ] Verify real-time subscriptions work correctly

### ✅ Security Configuration
- [ ] Review and update user role permissions
- [ ] Configure admin-only access controls
- [ ] Set up audit logging for all security operations
- [ ] Test emergency override functionality
- [ ] Verify fraud detection algorithms

### ✅ Mobile App Preparation
- [ ] Update app version and build numbers
- [ ] Configure production API endpoints
- [ ] Test on physical devices with real NFC wristbands
- [ ] Verify offline functionality works correctly
- [ ] Test ticket linking workflow end-to-end

### ✅ Staff Training Materials
- [ ] Create admin configuration guide
- [ ] Develop staff scanning procedures
- [ ] Document ticket linking workflow
- [ ] Prepare troubleshooting guides
- [ ] Record training videos

## 🗄️ Database Migration Script

```sql
-- Execute this in your Supabase SQL editor

-- 1. Add ticket linking configuration to events table
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS ticket_linking_mode text DEFAULT 'disabled' 
    CHECK (ticket_linking_mode = ANY (ARRAY['disabled'::text, 'optional'::text, 'required'::text])),
  ADD COLUMN IF NOT EXISTS allow_unlinked_entry boolean DEFAULT true;

-- 2. Create tickets table
CREATE TABLE IF NOT EXISTS public.tickets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  ticket_number text NOT NULL,
  ticket_category text NOT NULL,
  holder_name text,
  holder_email text,
  holder_phone text,
  status text NOT NULL DEFAULT 'unused' 
    CHECK (status = ANY (ARRAY['unused'::text, 'linked'::text, 'cancelled'::text])),
  linked_wristband_id uuid UNIQUE,
  linked_at timestamp with time zone,
  linked_by uuid,
  uploaded_at timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT tickets_pkey PRIMARY KEY (id),
  CONSTRAINT tickets_event_id_fkey FOREIGN KEY (event_id) 
    REFERENCES public.events(id) ON DELETE CASCADE,
  CONSTRAINT tickets_linked_wristband_id_fkey FOREIGN KEY (linked_wristband_id) 
    REFERENCES public.wristbands(id) ON DELETE SET NULL,
  CONSTRAINT tickets_linked_by_fkey FOREIGN KEY (linked_by) 
    REFERENCES auth.users(id),
  CONSTRAINT tickets_event_ticket_unique UNIQUE (event_id, ticket_number)
);

-- 3. Add ticket linking to wristbands table
ALTER TABLE public.wristbands
  ADD COLUMN IF NOT EXISTS linked_ticket_id uuid UNIQUE,
  ADD COLUMN IF NOT EXISTS linked_at timestamp with time zone,
  ADD COLUMN IF NOT EXISTS ticket_link_required boolean DEFAULT false;

-- Add foreign key constraint if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'wristbands_linked_ticket_id_fkey'
    ) THEN
        ALTER TABLE public.wristbands
        ADD CONSTRAINT wristbands_linked_ticket_id_fkey 
        FOREIGN KEY (linked_ticket_id) REFERENCES public.tickets(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 4. Create audit table
CREATE TABLE IF NOT EXISTS public.ticket_link_audit (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  ticket_id uuid,
  wristband_id uuid NOT NULL,
  action text NOT NULL CHECK (action = ANY (ARRAY[
    'link'::text, 
    'unlink'::text, 
    'link_attempt_failed'::text,
    'entry_allowed_no_ticket'::text,
    'entry_denied_no_ticket'::text
  ])),
  performed_by uuid NOT NULL,
  reason text,
  timestamp timestamp with time zone DEFAULT now(),
  metadata jsonb,
  
  CONSTRAINT ticket_link_audit_pkey PRIMARY KEY (id),
  CONSTRAINT ticket_link_audit_event_id_fkey FOREIGN KEY (event_id) 
    REFERENCES public.events(id) ON DELETE CASCADE,
  CONSTRAINT ticket_link_audit_ticket_id_fkey FOREIGN KEY (ticket_id) 
    REFERENCES public.tickets(id) ON DELETE CASCADE,
  CONSTRAINT ticket_link_audit_wristband_id_fkey FOREIGN KEY (wristband_id) 
    REFERENCES public.wristbands(id) ON DELETE CASCADE,
  CONSTRAINT ticket_link_audit_performed_by_fkey FOREIGN KEY (performed_by) 
    REFERENCES auth.users(id)
);

-- 5. Add ticket reference to checkin_logs
ALTER TABLE public.checkin_logs
  ADD COLUMN IF NOT EXISTS ticket_id uuid;

-- Add foreign key constraint if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'checkin_logs_ticket_id_fkey'
    ) THEN
        ALTER TABLE public.checkin_logs
        ADD CONSTRAINT checkin_logs_ticket_id_fkey 
        FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE SET NULL;
    END IF;
END $$;

-- 6. Create ticket uploads tracking
CREATE TABLE IF NOT EXISTS public.ticket_uploads (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL,
  uploaded_by uuid NOT NULL,
  filename text NOT NULL,
  total_tickets integer NOT NULL,
  successful_imports integer DEFAULT 0,
  failed_imports integer DEFAULT 0,
  upload_timestamp timestamp with time zone DEFAULT now(),
  metadata jsonb,
  
  CONSTRAINT ticket_uploads_pkey PRIMARY KEY (id),
  CONSTRAINT ticket_uploads_event_id_fkey FOREIGN KEY (event_id) 
    REFERENCES public.events(id) ON DELETE CASCADE,
  CONSTRAINT ticket_uploads_uploaded_by_fkey FOREIGN KEY (uploaded_by) 
    REFERENCES auth.users(id)
);

-- 7. Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_tickets_event_number ON public.tickets(event_id, ticket_number);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON public.tickets(event_id, status);
CREATE INDEX IF NOT EXISTS idx_wristbands_linked_ticket ON public.wristbands(linked_ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_link_audit_event ON public.ticket_link_audit(event_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_ticket_link_audit_ticket ON public.ticket_link_audit(ticket_id);
CREATE INDEX IF NOT EXISTS idx_checkin_logs_ticket ON public.checkin_logs(ticket_id);

-- 8. Set up Row Level Security (RLS)
ALTER TABLE public.tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_link_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_uploads ENABLE ROW LEVEL SECURITY;

-- RLS Policies for tickets
CREATE POLICY "Users can view tickets for their events" ON public.tickets
  FOR SELECT USING (
    event_id IN (
      SELECT event_id FROM public.event_access 
      WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage tickets" ON public.tickets
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.event_access ea
      JOIN public.user_profiles up ON ea.user_id = up.id
      WHERE ea.user_id = auth.uid() 
      AND ea.event_id = tickets.event_id
      AND up.role IN ('admin', 'owner')
    )
  );

-- RLS Policies for audit logs
CREATE POLICY "Users can view audit logs for their events" ON public.ticket_link_audit
  FOR SELECT USING (
    event_id IN (
      SELECT event_id FROM public.event_access 
      WHERE user_id = auth.uid()
    )
  );

-- RLS Policies for ticket uploads
CREATE POLICY "Users can manage uploads for their events" ON public.ticket_uploads
  FOR ALL USING (
    event_id IN (
      SELECT event_id FROM public.event_access 
      WHERE user_id = auth.uid()
    )
  );

-- 9. Create validation function
CREATE OR REPLACE FUNCTION validate_wristband_entry(
  p_wristband_id uuid,
  p_event_id uuid
) RETURNS TABLE (
  can_enter boolean,
  reason text,
  ticket_id uuid
) AS $$
DECLARE
  v_event_mode text;
  v_allow_unlinked boolean;
  v_wristband_requires_link boolean;
  v_linked_ticket_id uuid;
  v_wristband_active boolean;
BEGIN
  -- Get event settings
  SELECT ticket_linking_mode, allow_unlinked_entry
  INTO v_event_mode, v_allow_unlinked
  FROM events WHERE id = p_event_id;
  
  -- Get wristband info
  SELECT linked_ticket_id, ticket_link_required, is_active
  INTO v_linked_ticket_id, v_wristband_requires_link, v_wristband_active
  FROM wristbands WHERE id = p_wristband_id;
  
  -- Check if wristband is active
  IF NOT v_wristband_active THEN
    RETURN QUERY SELECT false, 'Wristband is deactivated'::text, NULL::uuid;
    RETURN;
  END IF;
  
  -- Apply validation rules based on event mode
  IF v_event_mode = 'disabled' THEN
    RETURN QUERY SELECT true, 'Entry allowed - No ticket system'::text, NULL::uuid;
    RETURN;
  END IF;
  
  IF v_event_mode = 'optional' THEN
    IF v_linked_ticket_id IS NOT NULL THEN
      RETURN QUERY SELECT true, 'Entry allowed - Ticket linked'::text, v_linked_ticket_id;
    ELSE
      RETURN QUERY SELECT true, 'Entry allowed - No ticket link (optional)'::text, NULL::uuid;
    END IF;
    RETURN;
  END IF;
  
  IF v_event_mode = 'required' THEN
    IF v_linked_ticket_id IS NOT NULL THEN
      RETURN QUERY SELECT true, 'Entry allowed - Ticket verified'::text, v_linked_ticket_id;
    ELSIF v_wristband_requires_link THEN
      RETURN QUERY SELECT false, 'Entry denied - Ticket link required'::text, NULL::uuid;
    ELSIF v_allow_unlinked THEN
      RETURN QUERY SELECT true, 'Entry allowed - Event allows unlinked'::text, NULL::uuid;
    ELSE
      RETURN QUERY SELECT false, 'Entry denied - No ticket linked'::text, NULL::uuid;
    END IF;
    RETURN;
  END IF;
  
  -- Default: deny
  RETURN QUERY SELECT false, 'Entry denied - Invalid configuration'::text, NULL::uuid;
END;
$$ LANGUAGE plpgsql;

COMMIT;
```

## 🔧 API Endpoint Configuration

### Required Supabase Functions
Create these in your Supabase Functions dashboard:

1. **ticket-validation** - Validates wristband entry
2. **ticket-linking** - Links tickets to wristbands
3. **fraud-analytics** - Generates security reports
4. **ticket-upload** - Bulk ticket import

### Environment Variables
```bash
# Production Supabase Configuration
SUPABASE_URL=your-production-url
SUPABASE_ANON_KEY=your-production-anon-key
SUPABASE_SERVICE_KEY=your-production-service-key

# Security Configuration
ENABLE_FRAUD_PREVENTION=true
MAX_LINKING_ATTEMPTS=3
AUDIT_LOG_RETENTION_DAYS=365
```

## 📱 Mobile App Configuration

### Production Build Settings
```swift
// Update in SupabaseService.swift
private let supabaseURL = "https://your-production-project.supabase.co"
private let supabaseAnonKey = "your-production-anon-key"

// Update app version in Info.plist
CFBundleShortVersionString: "2.0.0"
CFBundleVersion: "1"
```

### Required Permissions
- NFC Reading capability
- Network access for real-time sync
- Local storage for offline functionality

## 👥 Staff Training Guide

### For Administrators
1. **Event Setup**: Configure ticket linking mode per event
2. **Security Monitoring**: Review fraud analytics regularly
3. **Emergency Procedures**: Use override capabilities when needed
4. **Staff Management**: Assign appropriate roles and permissions

### For Gate Staff
1. **Normal Scanning**: Tap wristband → Allow/Deny entry
2. **Ticket Linking**: When prompted, search and select ticket
3. **Error Handling**: Follow on-screen instructions for issues
4. **Emergency Override**: Contact admin for special situations

### For Event Organizers
1. **Ticket Upload**: Import guest lists before event
2. **Real-time Monitoring**: Watch live analytics during event
3. **Post-event Reports**: Export fraud prevention metrics
4. **Revenue Protection**: Track prevented losses and ROI

## 🚨 Security Best Practices

### Access Control
- Limit admin access to trusted personnel only
- Use strong passwords and 2FA where possible
- Regularly audit user permissions and access logs
- Implement session timeouts for security

### Data Protection
- Enable database encryption at rest
- Use HTTPS for all API communications
- Implement proper backup and disaster recovery
- Follow GDPR/privacy regulations for attendee data

### Fraud Prevention
- Monitor fraud attempt patterns regularly
- Set up alerts for unusual activity
- Keep audit logs for compliance and investigation
- Train staff to recognize suspicious behavior

## 📊 Success Metrics

### Key Performance Indicators
- **Fraud Prevention Rate**: % of counterfeit attempts blocked
- **Revenue Protection**: Dollar amount saved from fraud
- **Linking Efficiency**: Average time to link ticket to wristband
- **Staff Adoption**: % of staff using system correctly
- **Customer Satisfaction**: Reduced wait times and smoother entry

### Monitoring Dashboard
Set up real-time monitoring for:
- Active fraud attempts
- System performance and uptime
- Staff scanning efficiency
- Revenue protection metrics
- Customer flow and wait times

## 🎯 Launch Checklist

### Pre-Launch (1 week before)
- [ ] Complete database migration
- [ ] Deploy mobile app updates
- [ ] Train all staff on new procedures
- [ ] Test with small group of attendees
- [ ] Verify backup and recovery procedures

### Launch Day
- [ ] Monitor system performance closely
- [ ] Have technical support team on standby
- [ ] Track fraud prevention metrics
- [ ] Gather staff feedback on usability
- [ ] Document any issues for improvement

### Post-Launch (1 week after)
- [ ] Analyze fraud prevention effectiveness
- [ ] Review staff feedback and training needs
- [ ] Calculate ROI and revenue protection
- [ ] Plan improvements for next event
- [ ] Update documentation based on learnings

## 🆘 Troubleshooting Guide

### Common Issues
1. **Wristband won't scan**: Check NFC chip integrity
2. **Ticket not found**: Verify ticket was uploaded correctly
3. **Linking fails**: Check network connectivity and permissions
4. **Admin settings locked**: Verify user has admin/owner role
5. **Offline mode issues**: Ensure local data is synced

### Emergency Procedures
1. **System down**: Use emergency override for critical entries
2. **Mass linking failure**: Switch to optional mode temporarily
3. **Fraud detected**: Document and report to security team
4. **Staff confusion**: Provide immediate retraining
5. **Customer complaints**: Escalate to event management

## 📞 Support Contacts

### Technical Support
- **Development Team**: [your-dev-team@company.com]
- **Database Admin**: [your-dba@company.com]
- **Security Team**: [security@company.com]

### Business Support
- **Event Management**: [events@company.com]
- **Customer Success**: [success@company.com]
- **Sales Team**: [sales@company.com]

---

**QuickStrap NFC is now ready for production deployment with enterprise-grade fraud prevention capabilities!** 🎯✨
