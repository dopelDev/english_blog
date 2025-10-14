#!/usr/bin/env sh
# Test script for seed file detection

echo "🔍 Testing seed file detection..."
echo ""

# Change to db-seed directory
cd /home/dopel/projects/english_blog/db-seed

# Test the detection functions
echo "📋 Available seed files:"
for file in *.sql *.sql.gz; do
  if [ -f "$file" ]; then
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
    echo "  📄 $file ($size, modified: $date)"
  fi
done

echo ""
echo "🧪 Testing auto-selection logic..."

# Test SQL files
echo "SQL files:"
for file in *.sql; do
  [ -f "$file" ] && [ "$file" != "*.sql" ] && echo "  - $file"
done

# Test GZ files  
echo "GZ files:"
for file in *.sql.gz; do
  [ -f "$file" ] && [ "$file" != "*.sql.gz" ] && echo "  - $file"
done

echo ""
echo "✅ Test completed. Run the actual script with:"
echo "   SEED_MODE=prep ./10-prepare-seed.sh"
