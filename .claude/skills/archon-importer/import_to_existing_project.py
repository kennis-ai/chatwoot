#!/usr/bin/env python3
"""
Import Current Codebase to Existing Archon Project

Simplified importer that adds documentation and code to an existing project.
Perfect for when you already have a project in Archon and want to add content.
"""

import asyncio
import sys
from pathlib import Path

from scan_repository import RepositoryScanner
from validate_archon_connection import ArchonValidator
from upload_to_archon import ArchonUploader


async def import_to_existing_project(
    project_id: str,
    archon_url: str = "http://localhost:8181",
    include_code_examples: bool = True,
    dry_run: bool = False,
) -> dict:
    """
    Import current codebase into an existing Archon project.

    Args:
        project_id: Existing Archon project ID
        archon_url: Archon backend URL
        include_code_examples: Extract code examples
        dry_run: Preview without making changes

    Returns:
        Import results
    """
    current_dir = Path.cwd().resolve()

    print(f"🔍 Importing to existing Archon project")
    print(f"   Source: {current_dir}")
    print(f"   Project ID: {project_id}")
    print()

    # Build config
    config = {
        "local_path": str(current_dir),
        "archon_backend_url": archon_url,
        "include_code_examples": include_code_examples,
        "project_id": project_id,
        "repository_path": str(current_dir),
        "doc_patterns": [
            "*.md",
            "*.rst",
            "*.txt",
            "docs/**/*",
            "documentation/**/*",
            "README*",
            "CONTRIBUTING*",
            "CHANGELOG*",
        ],
        "exclude_patterns": [
            "node_modules/**",
            ".git/**",
            "*.min.js",
            "*.min.css",
            "dist/**",
            "build/**",
            "__pycache__/**",
            ".venv/**",
            "venv/**",
            ".claude/**",
        ],
    }

    results = {
        "project_id": project_id,
        "status": "running",
        "documents_uploaded": 0,
        "code_examples": 0,
        "errors": [],
    }

    try:
        # Step 1: Validate connection
        print("🔐 Validating Archon connection...")
        validator = ArchonValidator(config)
        validation = await validator.validate()

        if not validation["backend_reachable"]:
            print("❌ Cannot reach Archon backend")
            results["status"] = "failed"
            results["errors"].append("Backend not reachable")
            return results

        if not validation["embedding_provider_configured"]:
            print("❌ Embedding provider not configured")
            results["status"] = "failed"
            results["errors"].append("Embedding provider required")
            return results

        print("  ✓ Archon backend reachable")
        print("  ✓ Embedding provider configured")

        # Step 2: Scan repository
        print("\n🔍 Scanning repository...")
        scanner = RepositoryScanner(config)
        scan_result = await scanner.scan()

        print(f"  ✓ Found {len(scan_result['readme_files'])} README files")
        print(f"  ✓ Found {len(scan_result['documentation'])} documentation files")
        if include_code_examples:
            print(f"  ✓ Found {len(scan_result['code_files'])} code files")
        print(f"  ✓ Estimated size: {scan_result['estimated_size_mb']:.2f} MB")

        total_files = len(scan_result["readme_files"]) + len(scan_result["documentation"])
        if total_files == 0:
            print("\n⚠️  No documentation files found to import")
            results["status"] = "success"
            return results

        if dry_run:
            print("\n✅ Dry run completed - would import:")
            print(f"   - {total_files} documentation files")
            if include_code_examples:
                print(f"   - {len(scan_result['code_files'])} code files")
            results["status"] = "success_dry_run"
            return results

        # Step 3: Upload documentation
        print("\n📤 Uploading documentation files...")
        uploader = ArchonUploader(config)
        doc_files = scan_result["readme_files"] + scan_result["documentation"]

        upload_result = await uploader.upload_documents(doc_files)

        print(f"  ✓ Uploaded {upload_result['successful']} files")
        if upload_result["failed"] > 0:
            print(f"  ⚠️  Failed: {upload_result['failed']} files")
            results["errors"].extend(upload_result["errors"])

        results["documents_uploaded"] = upload_result["successful"]

        # Step 4: Extract code examples
        if include_code_examples and scan_result["code_files"]:
            print("\n🔍 Extracting code examples...")
            code_result = await uploader.extract_code_examples(scan_result["code_files"])

            print(f"  ✓ Extracted {code_result['successful']} code examples")
            results["code_examples"] = code_result["successful"]

        # Success!
        print("\n✅ Import completed successfully!")
        print(f"   Project: {archon_url}/projects/{project_id}")
        print(f"   Uploaded: {results['documents_uploaded']} documents")
        if results["code_examples"] > 0:
            print(f"   Extracted: {results['code_examples']} code examples")

        results["status"] = "success"
        return results

    except Exception as e:
        print(f"\n❌ Import failed: {e}")
        results["status"] = "failed"
        results["errors"].append(str(e))
        return results


async def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(
        description="Import current codebase into existing Archon project"
    )

    parser.add_argument(
        "--project-id",
        required=True,
        help="Existing Archon project ID to import into",
    )
    parser.add_argument(
        "--archon-url",
        default="http://localhost:8181",
        help="Archon backend URL (default: http://localhost:8181)",
    )
    parser.add_argument(
        "--include-code-examples",
        action="store_true",
        default=True,
        help="Extract code examples (default: True)",
    )
    parser.add_argument(
        "--no-code-examples",
        dest="include_code_examples",
        action="store_false",
        help="Skip code example extraction",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be imported",
    )

    args = parser.parse_args()

    result = await import_to_existing_project(
        project_id=args.project_id,
        archon_url=args.archon_url,
        include_code_examples=args.include_code_examples,
        dry_run=args.dry_run,
    )

    sys.exit(0 if result["status"].startswith("success") else 1)


if __name__ == "__main__":
    asyncio.run(main())
