# Catálogo inicial

HU-CAT-001/002: categorías y productos en PostgreSQL. Ambos permiten SELECT público únicamente de activos; productos de categorías inactivas quedan ocultos. Anon/authenticated no pueden modificar catálogo ni precios. Se mantiene disponible separado de activo y no se implementa inventario.

La migración incorpora la sucursal confirmada de Carabayllo, siete categorías y tres productos de demostración. Todos los precios de la carta son **demostrativos, no oficiales**. La bandera demostracion facilita sustituir el contenido cuando el negocio lo confirme. Las fotografías son referenciales proporcionadas para el proyecto.

Identificadores UUID independientes del slug; índices en claves foráneas, constraints de precio y timestamp actualizado. Productos no tienen local_id: el catálogo es compartido y los pedidos elegirán una sucursal real. Las variantes se implementarán cuando exista una historia que las requiera.

Pruebas de CI ejecutan migraciones sobre PostgreSQL efímero y verifican lectura de activos, ocultación y prohibición de alterar precios. La migración se aplica en LYS mediante InsForge CLI. No se agregan secretos ni roles comerciales.
