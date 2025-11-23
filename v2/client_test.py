#!/usr/bin/env python3
"""
Test-Client für den Tanss MCP Server v2
"""

import asyncio
from fastmcp import Client

async def main():
    # Ersetze URL durch die Adresse deines laufenden MCP-Servers
    client = Client("http://localhost:8000/mcp")
    
    async with client:
        print("✅ Connected:", client.is_connected())
        
        # Tools auflisten
        tools = await client.list_tools()
        print("\n📋 Verfügbare Tools:")
        for tool in tools:
            print(f"  - {tool.name}: {tool.description}")
        
        # Test 1: Ticket-Kommentare abrufen
        print("\n🧪 Test 1: Ticket-Kommentare abrufen")
        print("-" * 50)
        result = await client.call_tool("get_ticket_comments", {"ticket_id": "123"})
        print(result)
        
        # Test 2: Ticket abrufen
        print("\n🧪 Test 2: Ticket abrufen")
        print("-" * 50)
        result = await client.call_tool("get_ticket", {"ticket_id": "123"})
        print(result)
        
        # Test 3: Tickets auflisten
        print("\n🧪 Test 3: Tickets auflisten")
        print("-" * 50)
        result = await client.call_tool("list_tickets", {"limit": 5, "offset": 0})
        print(result)

if __name__ == "__main__":
    asyncio.run(main())

